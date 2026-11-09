set script_dir [file dirname [file normalize [info script]]]
set rtl_dir [file normalize [file join $script_dir ".."]]
set root_dir [file normalize [file join $rtl_dir ".." ".."]]

set project_name "u55c_gen_smoketest_rtl"
if {[info exists ::env(U55C_RTL_PROJECT_NAME)] && $::env(U55C_RTL_PROJECT_NAME) ne ""} {
  set project_name $::env(U55C_RTL_PROJECT_NAME)
}

set xpr [file join $root_dir build vivado_rtl $project_name "$project_name.xpr"]
open_project $xpr
launch_simulation
run all
close_project
exit
