set script_dir [file dirname [file normalize [info script]]]
set hls_dir [file normalize [file join $script_dir ".."]]

set part "xcu55c-fsvh2892-2L-e"
if {[info exists ::env(U55C_PART)] && $::env(U55C_PART) ne ""} {
  set part $::env(U55C_PART)
}

open_project -reset drum_synth_hls
set_top drum_synth
add_files [file join $hls_dir src drum_synth.cpp]
add_files -tb [file join $hls_dir tb drum_synth_tb.cpp]
open_solution -reset solution1
set_part $part
create_clock -period 3.33
config_export -format xo

csim_design
csynth_design

if {[info exists ::env(U55C_HLS_RUN_COSIM)] && $::env(U55C_HLS_RUN_COSIM) eq "1"} {
  cosim_design
}

export_design -format xo -output [file join $hls_dir build drum_synth.xo]
exit
