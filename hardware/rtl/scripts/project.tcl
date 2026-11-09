set script_dir [file dirname [file normalize [info script]]]
set rtl_dir [file normalize [file join $script_dir ".."]]
set root_dir [file normalize [file join $rtl_dir ".." ".."]]

set project_name "u55c_gen_smoketest_rtl"
if {[info exists ::env(U55C_RTL_PROJECT_NAME)] && $::env(U55C_RTL_PROJECT_NAME) ne ""} {
  set project_name $::env(U55C_RTL_PROJECT_NAME)
}

set part "xcu55c-fsvh2892-2L-e"
if {[info exists ::env(U55C_PART)] && $::env(U55C_PART) ne ""} {
  set part $::env(U55C_PART)
}

set top_module "vector_add_rtl"
if {[info exists ::env(U55C_RTL_TOP)] && $::env(U55C_RTL_TOP) ne ""} {
  set top_module $::env(U55C_RTL_TOP)
}

set tb_top "vector_add_rtl_tb"
if {[info exists ::env(U55C_RTL_TB_TOP)] && $::env(U55C_RTL_TB_TOP) ne ""} {
  set tb_top $::env(U55C_RTL_TB_TOP)
}

set build_dir [file join $root_dir build vivado_rtl]
file mkdir $build_dir

create_project -force $project_name [file join $build_dir $project_name] -part $part
set_property target_language Verilog [current_project]

set src_files [glob -nocomplain [file join $rtl_dir src *.v] [file join $rtl_dir src *.sv]]
set tb_files [glob -nocomplain [file join $rtl_dir tb *.v] [file join $rtl_dir tb *.sv]]
if {[llength $src_files] == 0} {
  error "No RTL source files found under $rtl_dir/src"
}
if {[llength $tb_files] == 0} {
  error "No testbench files found under $rtl_dir/tb"
}

add_files $src_files
add_files -fileset sim_1 $tb_files

set_property top $top_module [get_filesets sources_1]
set_property top $tb_top [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

close_project
exit
