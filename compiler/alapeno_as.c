/* SPDX-License-Identifier: AGPL-3.0-only */

/*
 * Alapeno assembler: assembly text -> little-endian 32-bit ISA words.
 *
 * Syntax (one instruction per line; '#' starts a comment; blank lines ignored):
 *   registers: x0-x31 / X0-X31 and z0-z7 / Z0-Z7
 *   mnemonics (case-insensitive):
 *     add, sub, addi, andi, ld, sd, sw, lwu, lui, jal,
 *     beq, bne, mul.lo, zmac, modp, red.sum, halt
 *   R:  add rd, rs1, rs2
 *       sub rd, rs1, rs2
 *       mul.lo rd, rs1, rs2
 *   I:  addi rd, rs1, imm
 *       andi rd, rs1, imm
 *       ld  rd, imm(rs1)
 *       lwu rd, imm(rs1)
 *       lui rd, imm          ; rs1 encoded 0; imm16 becomes X[rd][31:16]
 *       jal rd, imm|label    ; rs1 encoded 0; imm = signed byte PC offset
 *   S:  sd rs2, imm(rs1)
 *       sw rs2, imm(rs1)
 *   B:  beq rs1, rs2, imm|label
 *       bne rs1, rs2, imm|label
 *   Z:  zmac zd, xsrc1, xsrc2
 *       modp zd, zsrc         ; src2 encoded 0
 *   RED: red.sum zd, xbase, xlen
 *   halt                      ; rd=rs1=rs2=funct=0
 *
 * Labels: "name:" on its own or before an instruction. Branch/JAL targets
 * may be a label (PC-relative byte offset) or a numeric imm.
 *
 * imm: signed decimal or 0x hex fitting signed imm16, except LUI which
 * takes a 16-bit field value (0..0xFFFF or signed equiv) per ISA.md §6.
 *
 * Usage: alapeno_as <input.s> <output.bin>
 * Writes raw LE words to output.bin; prints "addr: word  ; source" on stdout.
 *
 * Field layout (ISA.md §3), word bits:
 *   R:   [31:26] op, [25:21] rd,  [20:16] rs1, [15:11] rs2, [10:0] funct
 *   I:   [31:26] op, [25:21] rd,  [20:16] rs1, [15:0]  imm16
 *   S:   [31:26] op, [25:21] rs2, [20:16] rs1, [15:0]  imm16
 *   B:   [31:26] op, [25:21] rs1, [20:16] rs2, [15:0]  imm16
 *   Z:   [31:26] op, [25:21] zd,  [20:16] src1,[15:11] src2,
 *        [10:8] funct3, [7:0] = 0
 *   RED: op 0x19, zd [25:21], base rs1 [20:16], length rs2 [15:11], funct [10:0]
 *
 * Known: ADD x1, x2, x3 = 0x00221800 (LE bytes 00 18 22 00).
 */

#include <ctype.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE   512
#define MAX_LINES  4096
#define MAX_LABELS 1024
#define MAX_NAME   64

enum {
  OP_ADD = 0x00,
  OP_SUB = 0x01,
  OP_ANDI = 0x11,
  OP_ADDI = 0x10,
  OP_LUI = 0x16,
  OP_Z = 0x18,
  OP_RED = 0x19,
  OP_LD = 0x20,
  OP_LWU = 0x24,
  OP_SD = 0x28,
  OP_SW = 0x29,
  OP_BEQ = 0x30,
  OP_BNE = 0x31,
  OP_JAL = 0x36,
  OP_MUL_LO = 0x0C,
  OP_HALT = 0x3E,
  F3_ZMAC = 6,
  F3_MODP = 7,
  F_RED_SUM = 0
};

typedef enum {
  KIND_R,
  KIND_I,
  KIND_S,
  KIND_B,
  KIND_Z,
  KIND_RED,
  KIND_HALT,
  KIND_LUI,
  KIND_JAL,
  KIND_MODP
} kind_t;

typedef struct {
  char name[MAX_NAME];
  int pc; /* byte address */
} label_t;

typedef struct {
  char src[MAX_LINE];
  char mnem[32];
  kind_t kind;
  int op;
  int rd, rs1, rs2; /* or zd/src */
  int funct;
  int32_t imm;
  int has_imm;
  char target[MAX_NAME]; /* label name if non-empty */
  int lineno;
  int pc;
  uint32_t word;
} insn_t;

static label_t labels[MAX_LABELS];
static int nlabels;
static insn_t insns[MAX_LINES];
static int ninsns;

static void die(const char *msg) {
  fprintf(stderr, "alapeno_as: %s\n", msg);
  exit(1);
}


static void diei(const char *fmt, int n) {
  fprintf(stderr, "alapeno_as: ");
  fprintf(stderr, fmt, n);
  fprintf(stderr, "\n");
  exit(1);
}

static char *skip_ws(char *s) {
  while (*s && isspace((unsigned char)*s)) s++;
  return s;
}

static void strip_comment(char *s) {
  char *p = s;
  while (*p) {
    if (*p == '#') {
      *p = '\0';
      return;
    }
    p++;
  }
}

static void rtrim(char *s) {
  size_t n = strlen(s);
  while (n > 0 && isspace((unsigned char)s[n - 1])) {
    s[--n] = '\0';
  }
}

static int streq_ci(const char *a, const char *b) {
  while (*a && *b) {
    if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return 0;
    a++;
    b++;
  }
  return *a == '\0' && *b == '\0';
}

static int parse_xreg(const char *tok, int *out) {
  if (tok[0] != 'x' && tok[0] != 'X') return -1;
  char *end = NULL;
  long v = strtol(tok + 1, &end, 10);
  if (end == tok + 1 || *end != '\0') return -1;
  if (v < 0 || v > 31) return -1;
  *out = (int)v;
  return 0;
}

static int parse_zreg(const char *tok, int *out) {
  if (tok[0] != 'z' && tok[0] != 'Z') return -1;
  char *end = NULL;
  long v = strtol(tok + 1, &end, 10);
  if (end == tok + 1 || *end != '\0') return -1;
  if (v < 0 || v > 7) return -1;
  *out = (int)v;
  return 0;
}

/* Parse signed imm16 (or raw 16-bit for LUI). Returns 0 on success. */
static int parse_imm(const char *tok, int32_t *out, int lui_mode) {
  char *end = NULL;
  long v;
  errno = 0;
  if (tok[0] == '0' && (tok[1] == 'x' || tok[1] == 'X')) {
    v = strtol(tok, &end, 16);
  } else {
    v = strtol(tok, &end, 10);
  }
  if (end == tok || *end != '\0' || errno == ERANGE) return -1;
  if (lui_mode) {
    /* Accept 0..65535 or signed -32768..32767; store low 16 bits. */
    if (v < -32768 || v > 65535) return -1;
    *out = (int32_t)(v & 0xFFFF);
    return 0;
  }
  if (v < -32768 || v > 32767) return -1;
  *out = (int32_t)v;
  return 0;
}

static int find_label(const char *name) {
  int i;
  for (i = 0; i < nlabels; i++) {
    if (strcmp(labels[i].name, name) == 0) return i;
  }
  return -1;
}

static void add_label(const char *name, int pc, int lineno) {
  int i = find_label(name);
  if (i >= 0) diei("duplicate label at line %d", lineno);
  if (nlabels >= MAX_LABELS) die("too many labels");
  if (strlen(name) >= MAX_NAME) diei("label too long at line %d", lineno);
  strcpy(labels[nlabels].name, name);
  labels[nlabels].pc = pc;
  nlabels++;
}

static uint32_t enc_r(int op, int rd, int rs1, int rs2, int funct) {
  return ((uint32_t)op << 26) | ((uint32_t)rd << 21) | ((uint32_t)rs1 << 16) |
         ((uint32_t)rs2 << 11) | ((uint32_t)funct & 0x7FF);
}

static uint32_t enc_i(int op, int rd, int rs1, int32_t imm) {
  return ((uint32_t)op << 26) | ((uint32_t)rd << 21) | ((uint32_t)rs1 << 16) |
         ((uint32_t)imm & 0xFFFF);
}

static uint32_t enc_s(int op, int rs2, int rs1, int32_t imm) {
  return ((uint32_t)op << 26) | ((uint32_t)rs2 << 21) | ((uint32_t)rs1 << 16) |
         ((uint32_t)imm & 0xFFFF);
}

static uint32_t enc_b(int op, int rs1, int rs2, int32_t imm) {
  return ((uint32_t)op << 26) | ((uint32_t)rs1 << 21) | ((uint32_t)rs2 << 16) |
         ((uint32_t)imm & 0xFFFF);
}

static uint32_t enc_z(int op, int zd, int src1, int src2, int funct3) {
  return ((uint32_t)op << 26) | ((uint32_t)zd << 21) | ((uint32_t)src1 << 16) |
         ((uint32_t)src2 << 11) | ((uint32_t)(funct3 & 7) << 8);
}

/* Split "imm(reg)" into imm token and reg token. mutates s. */
static int split_mem(char *s, char **imm_out, char **reg_out) {
  char *lp = strchr(s, '(');
  char *rp;
  if (!lp) return -1;
  *lp = '\0';
  rp = strchr(lp + 1, ')');
  if (!rp || *(rp + 1) != '\0') return -1;
  *rp = '\0';
  *imm_out = skip_ws(s);
  *reg_out = skip_ws(lp + 1);
  rtrim(*imm_out);
  rtrim(*reg_out);
  if (**imm_out == '\0' || **reg_out == '\0') return -1;
  return 0;
}

/* Tokenize comma-separated args into up to 3 tokens (modifies buf). */
static int split_args(char *buf, char *tok[], int max_tok) {
  int n = 0;
  char *p = buf;
  while (*p && n < max_tok) {
    p = skip_ws(p);
    if (*p == '\0') break;
    tok[n++] = p;
    while (*p && *p != ',') p++;
    if (*p == ',') {
      *p = '\0';
      p++;
    }
    rtrim(tok[n - 1]);
  }
  p = skip_ws(p);
  if (*p != '\0') return -1; /* extra junk */
  return n;
}

static int classify(const char *mnem, insn_t *ins) {
  if (streq_ci(mnem, "add")) {
    ins->kind = KIND_R; ins->op = OP_ADD; ins->funct = 0; return 0;
  }
  if (streq_ci(mnem, "sub")) {
    ins->kind = KIND_R; ins->op = OP_SUB; ins->funct = 0; return 0;
  }
  if (streq_ci(mnem, "mul.lo")) {
    ins->kind = KIND_R; ins->op = OP_MUL_LO; ins->funct = 0; return 0;
  }
  if (streq_ci(mnem, "addi")) {
    ins->kind = KIND_I; ins->op = OP_ADDI; return 0;
  }
  if (streq_ci(mnem, "andi")) {
    ins->kind = KIND_I; ins->op = OP_ANDI; return 0;
  }
  if (streq_ci(mnem, "ld")) {
    ins->kind = KIND_I; ins->op = OP_LD; return 0;
  }
  if (streq_ci(mnem, "lwu")) {
    ins->kind = KIND_I; ins->op = OP_LWU; return 0;
  }
  if (streq_ci(mnem, "lui")) {
    ins->kind = KIND_LUI; ins->op = OP_LUI; return 0;
  }
  if (streq_ci(mnem, "jal")) {
    ins->kind = KIND_JAL; ins->op = OP_JAL; return 0;
  }
  if (streq_ci(mnem, "sd")) {
    ins->kind = KIND_S; ins->op = OP_SD; return 0;
  }
  if (streq_ci(mnem, "sw")) {
    ins->kind = KIND_S; ins->op = OP_SW; return 0;
  }
  if (streq_ci(mnem, "beq")) {
    ins->kind = KIND_B; ins->op = OP_BEQ; return 0;
  }
  if (streq_ci(mnem, "bne")) {
    ins->kind = KIND_B; ins->op = OP_BNE; return 0;
  }
  if (streq_ci(mnem, "zmac")) {
    ins->kind = KIND_Z; ins->op = OP_Z; ins->funct = F3_ZMAC; return 0;
  }
  if (streq_ci(mnem, "modp")) {
    ins->kind = KIND_MODP; ins->op = OP_Z; ins->funct = F3_MODP; return 0;
  }
  if (streq_ci(mnem, "red.sum")) {
    ins->kind = KIND_RED; ins->op = OP_RED; ins->funct = F_RED_SUM; return 0;
  }
  if (streq_ci(mnem, "halt")) {
    ins->kind = KIND_HALT; ins->op = OP_HALT; return 0;
  }
  return -1;
}

static int is_ident_start(char c) {
  return isalpha((unsigned char)c) || c == '_';
}

static int is_ident(char c) {
  return isalnum((unsigned char)c) || c == '_';
}

static int looks_like_label_ref(const char *tok) {
  const char *p;
  if (!is_ident_start(*tok)) return 0;
  /* not a register */
  if ((tok[0] == 'x' || tok[0] == 'X' || tok[0] == 'z' || tok[0] == 'Z') &&
      isdigit((unsigned char)tok[1]))
    return 0;
  for (p = tok; *p; p++) {
    if (!is_ident(*p) && *p != '.') return 0;
  }
  return 1;
}

static void parse_insn_line(char *line, int lineno, int pc) {
  char buf[MAX_LINE];
  char *p, *mnem, *args;
  char *tok[4];
  int nt;
  insn_t *ins;

  strncpy(buf, line, MAX_LINE - 1);
  buf[MAX_LINE - 1] = '\0';
  p = skip_ws(buf);
  if (*p == '\0') return;

  /* Optional leading label: name: */
  if (is_ident_start(*p)) {
    char *q = p;
    while (is_ident(*q) || *q == '.') q++;
    if (*q == ':') {
      char name[MAX_NAME];
      size_t len = (size_t)(q - p);
      if (len == 0 || len >= MAX_NAME) diei("bad label at line %d", lineno);
      memcpy(name, p, len);
      name[len] = '\0';
      add_label(name, pc, lineno);
      p = skip_ws(q + 1);
      if (*p == '\0') return; /* label-only line */
    }
  }

  if (ninsns >= MAX_LINES) die("too many instructions");
  ins = &insns[ninsns];
  memset(ins, 0, sizeof(*ins));
  strncpy(ins->src, line, MAX_LINE - 1);
  ins->lineno = lineno;
  ins->pc = pc;

  mnem = p;
  while (*p && !isspace((unsigned char)*p)) p++;
  if (*p) {
    *p = '\0';
    p++;
  }
  strncpy(ins->mnem, mnem, sizeof(ins->mnem) - 1);
  if (classify(ins->mnem, ins) != 0) diei("unknown mnemonic at line %d", lineno);

  args = skip_ws(p);
  rtrim(args);

  switch (ins->kind) {
  case KIND_HALT:
    if (*args != '\0') diei("halt takes no operands at line %d", lineno);
    ins->rd = ins->rs1 = ins->rs2 = 0;
    ins->funct = 0;
    break;

  case KIND_R:
    nt = split_args(args, tok, 3);
    if (nt != 3) diei("R-type expects rd, rs1, rs2 at line %d", lineno);
    if (parse_xreg(tok[0], &ins->rd) || parse_xreg(tok[1], &ins->rs1) ||
        parse_xreg(tok[2], &ins->rs2))
      diei("bad register in R-type at line %d", lineno);
    break;

  case KIND_I: /* addi/andi or ld/lwu mem form */
    if (streq_ci(ins->mnem, "ld") || streq_ci(ins->mnem, "lwu")) {
      char *imm_s, *reg_s;
      nt = split_args(args, tok, 2);
      if (nt != 2) diei("load expects rd, imm(rs1) at line %d", lineno);
      if (parse_xreg(tok[0], &ins->rd)) diei("bad rd at line %d", lineno);
      if (split_mem(tok[1], &imm_s, &reg_s)) diei("bad mem operand at line %d", lineno);
      if (parse_xreg(reg_s, &ins->rs1)) diei("bad rs1 at line %d", lineno);
      if (parse_imm(imm_s, &ins->imm, 0)) diei("bad imm at line %d", lineno);
      ins->has_imm = 1;
    } else {
      /* addi / andi */
      nt = split_args(args, tok, 3);
      if (nt != 3) diei("I-type expects rd, rs1, imm at line %d", lineno);
      if (parse_xreg(tok[0], &ins->rd) || parse_xreg(tok[1], &ins->rs1))
        diei("bad register at line %d", lineno);
      if (parse_imm(tok[2], &ins->imm, 0)) diei("bad imm at line %d", lineno);
      ins->has_imm = 1;
    }
    break;

  case KIND_LUI:
    nt = split_args(args, tok, 2);
    if (nt != 2) diei("lui expects rd, imm at line %d", lineno);
    if (parse_xreg(tok[0], &ins->rd)) diei("bad rd at line %d", lineno);
    if (parse_imm(tok[1], &ins->imm, 1)) diei("bad lui imm at line %d", lineno);
    ins->rs1 = 0; /* ISA: LUI does not use rs1; encode 0 */
    ins->has_imm = 1;
    break;

  case KIND_JAL:
    nt = split_args(args, tok, 2);
    if (nt != 2) diei("jal expects rd, imm|label at line %d", lineno);
    if (parse_xreg(tok[0], &ins->rd)) diei("bad rd at line %d", lineno);
    ins->rs1 = 0; /* must be 0 */
    if (looks_like_label_ref(tok[1])) {
      strncpy(ins->target, tok[1], MAX_NAME - 1);
    } else {
      if (parse_imm(tok[1], &ins->imm, 0)) diei("bad jal imm at line %d", lineno);
      ins->has_imm = 1;
    }
    break;

  case KIND_S:
    {
      char *imm_s, *reg_s;
      nt = split_args(args, tok, 2);
      if (nt != 2) diei("store expects rs2, imm(rs1) at line %d", lineno);
      if (parse_xreg(tok[0], &ins->rs2)) diei("bad rs2 at line %d", lineno);
      if (split_mem(tok[1], &imm_s, &reg_s)) diei("bad mem operand at line %d", lineno);
      if (parse_xreg(reg_s, &ins->rs1)) diei("bad rs1 at line %d", lineno);
      if (parse_imm(imm_s, &ins->imm, 0)) diei("bad imm at line %d", lineno);
      ins->has_imm = 1;
    }
    break;

  case KIND_B:
    nt = split_args(args, tok, 3);
    if (nt != 3) diei("branch expects rs1, rs2, imm|label at line %d", lineno);
    if (parse_xreg(tok[0], &ins->rs1) || parse_xreg(tok[1], &ins->rs2))
      diei("bad register in branch at line %d", lineno);
    if (looks_like_label_ref(tok[2])) {
      strncpy(ins->target, tok[2], MAX_NAME - 1);
    } else {
      if (parse_imm(tok[2], &ins->imm, 0)) diei("bad branch imm at line %d", lineno);
      ins->has_imm = 1;
    }
    break;

  case KIND_Z:
    nt = split_args(args, tok, 3);
    if (nt != 3) diei("zmac expects zd, xsrc1, xsrc2 at line %d", lineno);
    if (parse_zreg(tok[0], &ins->rd)) diei("bad zd at line %d", lineno);
    if (parse_xreg(tok[1], &ins->rs1) || parse_xreg(tok[2], &ins->rs2))
      diei("bad x source at line %d", lineno);
    break;

  case KIND_MODP:
    nt = split_args(args, tok, 2);
    if (nt != 2) diei("modp expects zd, zsrc at line %d", lineno);
    if (parse_zreg(tok[0], &ins->rd) || parse_zreg(tok[1], &ins->rs1))
      diei("bad z register at line %d", lineno);
    ins->rs2 = 0;
    break;

  case KIND_RED:
    nt = split_args(args, tok, 3);
    if (nt != 3) diei("red.sum expects zd, xbase, xlen at line %d", lineno);
    if (parse_zreg(tok[0], &ins->rd)) diei("bad zd at line %d", lineno);
    if (parse_xreg(tok[1], &ins->rs1) || parse_xreg(tok[2], &ins->rs2))
      diei("bad x register at line %d", lineno);
    break;
  }

  ninsns++;
}

static void resolve_and_encode(void) {
  int i;
  for (i = 0; i < ninsns; i++) {
    insn_t *ins = &insns[i];
    int32_t imm = ins->imm;

    if (ins->target[0] != '\0') {
      int li = find_label(ins->target);
      int32_t off;
      if (li < 0) {
        fprintf(stderr, "alapeno_as: undefined label '%s' at line %d\n",
                ins->target, ins->lineno);
        exit(1);
      }
      off = (int32_t)labels[li].pc - (int32_t)ins->pc;
      if (off < -32768 || off > 32767) diei("branch offset out of range at line %d", ins->lineno);
      if ((off & 3) != 0) diei("branch offset not multiple of 4 at line %d", ins->lineno);
      imm = off;
      ins->has_imm = 1;
    }

    switch (ins->kind) {
    case KIND_R:
      ins->word = enc_r(ins->op, ins->rd, ins->rs1, ins->rs2, ins->funct);
      break;
    case KIND_I:
      ins->word = enc_i(ins->op, ins->rd, ins->rs1, imm);
      break;
    case KIND_LUI:
      ins->word = enc_i(ins->op, ins->rd, 0, imm);
      break;
    case KIND_JAL:
      if ((imm & 3) != 0) diei("jal offset not multiple of 4 at line %d", ins->lineno);
      ins->word = enc_i(ins->op, ins->rd, 0, imm);
      break;
    case KIND_S:
      ins->word = enc_s(ins->op, ins->rs2, ins->rs1, imm);
      break;
    case KIND_B:
      if ((imm & 3) != 0) diei("branch offset not multiple of 4 at line %d", ins->lineno);
      ins->word = enc_b(ins->op, ins->rs1, ins->rs2, imm);
      break;
    case KIND_Z:
      ins->word = enc_z(ins->op, ins->rd, ins->rs1, ins->rs2, ins->funct);
      break;
    case KIND_MODP:
      ins->word = enc_z(ins->op, ins->rd, ins->rs1, 0, ins->funct);
      break;
    case KIND_RED:
      ins->word = enc_r(ins->op, ins->rd, ins->rs1, ins->rs2, ins->funct);
      break;
    case KIND_HALT:
      ins->word = enc_r(ins->op, 0, 0, 0, 0);
      break;
    }
  }
}

static void first_pass(FILE *in) {
  char line[MAX_LINE];
  char raw[MAX_LINE];
  int lineno = 0;
  int pc = 0;

  while (fgets(line, sizeof(line), in)) {
    lineno++;
    strncpy(raw, line, MAX_LINE - 1);
    raw[MAX_LINE - 1] = '\0';
    /* strip newline */
    {
      size_t n = strlen(raw);
      while (n > 0 && (raw[n - 1] == '\n' || raw[n - 1] == '\r')) raw[--n] = '\0';
    }
    strip_comment(raw);
    rtrim(raw);
    {
      char *p = skip_ws(raw);
      int before = ninsns;
      if (*p == '\0') continue;
      parse_insn_line(raw, lineno, pc);
      if (ninsns > before) pc += 4;
    }
  }
}

int main(int argc, char **argv) {
  FILE *in, *out;
  int i;

  if (argc != 3) {
    fprintf(stderr, "usage: %s <input.s> <output.bin>\n", argv[0]);
    return 1;
  }

  in = fopen(argv[1], "r");
  if (!in) {
    perror(argv[1]);
    return 1;
  }
  first_pass(in);
  fclose(in);

  resolve_and_encode();

  /* Verify known ADD encoding before any success claim path. */
  for (i = 0; i < ninsns; i++) {
    if (streq_ci(insns[i].mnem, "add") && insns[i].rd == 1 &&
        insns[i].rs1 == 2 && insns[i].rs2 == 3) {
      if (insns[i].word != 0x00221800u) {
        fprintf(stderr,
                "alapeno_as: ADD x1,x2,x3 encoded 0x%08X, expected 0x00221800 — STOP\n",
                insns[i].word);
        return 1;
      }
    }
  }

  out = fopen(argv[2], "wb");
  if (!out) {
    perror(argv[2]);
    return 1;
  }

  for (i = 0; i < ninsns; i++) {
    uint32_t w = insns[i].word;
    unsigned char b[4];
    b[0] = (unsigned char)(w & 0xFF);
    b[1] = (unsigned char)((w >> 8) & 0xFF);
    b[2] = (unsigned char)((w >> 16) & 0xFF);
    b[3] = (unsigned char)((w >> 24) & 0xFF);
    if (fwrite(b, 1, 4, out) != 4) {
      perror("write");
      fclose(out);
      return 1;
    }
    printf("%08x: %08x  ; %s\n", insns[i].pc, w, insns[i].src);
  }
  fclose(out);
  return 0;
}
