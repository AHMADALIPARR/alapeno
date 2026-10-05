# SPDX-License-Identifier: AGPL-3.0-only
# Fold and share address arithmetic before expanding dynamic byte selectors.
# Bounded mapping stages avoid large temporary carry and multiplexer graphs.
set build [lindex $argv 0]
set top [lindex $argv 1]
proc checkpoint {build top} {
    yosys "write_json $build/$top-mapping-checkpoint.tmp.json"
    file rename -force "$build/$top-mapping-checkpoint.tmp.json" "$build/$top-mapping-checkpoint.json"
}
proc selected_listing {path selection} {
    yosys "select $selection"
    yosys "select -write $path"
    set handle [open $path r]
    set listing [string trim [read $handle]]
    close $handle
    return $listing
}
set components {alapeno_mem alapeno_accel alapeno_core alapeno_dma alapeno_matrix alapeno_vector alapeno_top}
if {$top eq "alapeno_tile_ctrl"} { set components {alapeno_tile_ctrl} }
foreach component $components {
    set filter [format {%s*/t:$* %s*/t:$_* %%d %s*/t:$mem_v2 %%d} $component $component $component]
    # Simple operators can be expanded together; arithmetic and dynamic
    # shifts need stages with constant folding and width reduction.
    set simple [format {%s %s*/t:$alu %%d %s*/t:$macc_v2 %%d %s*/t:$shiftx %%d %s*/t:$fa %%d %s*/t:$lcu %%d %s*/t:$macc %%d} $filter $component $component $component $component $component $component]
    yosys "select $simple"
    yosys techmap
    yosys "select -clear"
    yosys "opt -fast -purge $component*"
    checkpoint $build $top
    set previous_batch {}
    set iteration 0
    while {1} {
        set arithmetic [format {%s %s*/t:$shiftx %%d} $filter $component]
        set listing [selected_listing "$build/$top-map-remaining.txt" $arithmetic]
        if {$listing eq ""} { set listing [selected_listing "$build/$top-map-remaining.txt" $filter] }
        if {$listing eq ""} { break }
        set cells [lsort -ascii [split $listing "\n"]]
        set batch [lrange $cells 0 511]
        if {$batch eq $previous_batch} { error "Technology mapping made no progress in $component" }
        set previous_batch $batch
        set handle [open "$build/$top-map-batch.txt" w]
        puts $handle [join $batch "\n"]
        close $handle
        yosys "select -read $build/$top-map-batch.txt"
        yosys "techmap -max_iter 1"
        yosys "select -clear"
        yosys "opt -fast -purge $component*"
        yosys "wreduce $component*"
        yosys "opt -fast -purge $component*"
        # Fully expand only light operators created by this arithmetic stage.
        # Keep carries, full adders and multipliers for the next bounded stage.
        yosys "select $simple"
        yosys techmap
        yosys "select -clear"
        yosys "opt -fast -purge $component*"
        incr iteration
        if {$iteration % 4 == 0} { checkpoint $build $top }
        puts "MAP_BATCH $component iteration=$iteration remaining_before=[llength $cells] mapped=[llength $batch]"
        flush stdout
    }
    checkpoint $build $top
}
yosys "select -clear"
