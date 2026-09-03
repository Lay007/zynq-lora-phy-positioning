set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir "../../.."]]

if {[info exists ::env(ZYNQ_SDR_COURSE_ROOT)]} {
  set course_root [file normalize $::env(ZYNQ_SDR_COURSE_ROOT)]
} else {
  set course_root [file normalize [file join $repo_root "../zynq-sdr-course"]]
}

set vendor_dir [file join $course_root hardware 7020_ad936x_sdr hdl adi_fmcomms2_reference]
set project_name "lora_receiver_clg400"
set project_root [file join $repo_root fpga build clg400-board]
set xpr_path [file join $project_root "${project_name}.xpr"]

if {![file exists $xpr_path]} {
  puts "ERROR: missing project $xpr_path; run system_project.tcl first."
  exit 2
}

set ADI_USE_OOC_SYNTHESIS 0
set ADI_USE_INCR_COMP 0
source [file join $vendor_dir projects scripts adi_env.tcl]
source [file join $vendor_dir projects scripts adi_project_xilinx.tcl]

set original_dir [pwd]
set run_failed [catch {
  cd $project_root
  open_project $xpr_path
  if {[llength [get_runs -quiet impl_1]] != 0} {
    reset_run impl_1
  }

  # The full receiver is close enough to the 62.5 MHz boundary that the
  # default router can leave a seed-dependent single-path violation of only a
  # few picoseconds. Keep the sign-off flow reproducible: spend the extra
  # implementation effort and allow a post-route physical optimization pass
  # before accepting or exporting a bitstream.
  set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore \
    [get_runs impl_1]
  set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true \
    [get_runs impl_1]
  set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore \
    [get_runs impl_1]

  # Preserve a completed synthesis run. On Windows this design takes tens of
  # minutes to synthesize, and the Vivado run launcher can remain alive after
  # the checkpoint and completion marker have already been written.
  set synth_status [get_property STATUS [get_runs synth_1]]
  if {![string match "*Complete*" $synth_status]} {
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    set synth_status [get_property STATUS [get_runs synth_1]]
  }
  puts "SYNTH_STATUS: $synth_status"
  if {![string match "*Complete*" $synth_status]} {
    error "Synthesis is not complete; refusing to start implementation."
  }

  open_run synth_1
  if {![info exists ::env(ADI_NO_BITSTREAM_COMPRESSION)] &&
      ![info exists ADI_NO_BITSTREAM_COMPRESSION]} {
    set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
  }

  launch_runs impl_1 -to_step write_bitstream -jobs 4
  wait_on_run impl_1
  set impl_status [get_property STATUS [get_runs impl_1]]
  puts "IMPL_STATUS: $impl_status"
  if {![string match "*Complete*" $impl_status]} {
    error "Implementation did not complete successfully."
  }

  open_run impl_1
  report_timing_summary -warn_on_violation \
    -file [file join $project_root timing_impl.log]
  set timing_string [report_timing_summary -return_string]
  file mkdir [file join $project_root ${project_name}.sdk]
  if {[string match "*VIOLATED*" $timing_string] ||
      [string match "*Timing constraints are not met*" $timing_string]} {
    write_hw_platform -fixed -force -include_bit \
      -file [file join $project_root ${project_name}.sdk system_top_bad_timing.xsa]
    error "Implementation timing constraints are not met."
  }
  write_hw_platform -fixed -force -include_bit \
    -file [file join $project_root ${project_name}.sdk system_top.xsa]
} run_error run_options]
cd $original_dir
if {$run_failed} {
  return -options $run_options $run_error
}

puts "Implementation finished for $project_name"
puts "Bitstream/XSA: [file join $project_root ${project_name}.sdk]"
