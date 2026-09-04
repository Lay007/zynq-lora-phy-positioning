# Export the hardware platform (XSA) from an already implemented run.
#
# build_bitstream.tcl writes the XSA as its final step. That export can be lost
# if the Vivado session is interrupted after write_bitstream, and re-running the
# whole implementation would produce a different placement/routing seed. This
# script re-opens the existing implemented run and exports the XSA from it, so
# the bitstream that was already checked against timing stays the one that ships.

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir "../../.."]]

set project_name "lora_receiver_clg400"
set project_root [file join $repo_root fpga build clg400-board]
set xpr_path [file join $project_root "${project_name}.xpr"]
set sdk_dir [file join $project_root "${project_name}.sdk"]
set xsa_path [file join $sdk_dir system_top.xsa]

if {![file exists $xpr_path]} {
  puts "ERROR: missing project $xpr_path; run system_project.tcl first."
  exit 2
}

set original_dir [pwd]
set run_failed [catch {
  cd $project_root
  open_project $xpr_path

  set impl_status [get_property STATUS [get_runs impl_1]]
  set impl_bit [file join $project_root "${project_name}.runs" impl_1 system_top.bit]
  puts "IMPL_STATUS: $impl_status"
  if {![string match "*Complete*" $impl_status] || ![file exists $impl_bit]} {
    error "impl_1 has not completed write_bitstream; refusing to export."
  }

  open_run impl_1
  set timing_string [report_timing_summary -return_string]
  if {[string match "*VIOLATED*" $timing_string] ||
      [string match "*Timing constraints are not met*" $timing_string]} {
    error "Implemented run does not meet timing; refusing to export."
  }

  file mkdir $sdk_dir
  write_hw_platform -fixed -force -include_bit -file $xsa_path
  puts "XSA_PATH: $xsa_path"
  puts "XSA_BYTES: [file size $xsa_path]"
} run_error run_options]
cd $original_dir
if {$run_failed} {
  return -options $run_options $run_error
}

puts "Hardware platform exported for $project_name"
