set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir "../../.."]]

if {[info exists ::env(ZYNQ_SDR_COURSE_ROOT)]} {
  set course_root [file normalize $::env(ZYNQ_SDR_COURSE_ROOT)]
} else {
  set course_root [file normalize [file join $repo_root "../zynq-sdr-course"]]
}

set course_shell_dir [file join $course_root hardware 7020_ad936x_sdr hdl course_bpsk_fmcomms2_zc702]
set vendor_shell_bd [file join $course_shell_dir vendor_system_bd_clg400.tcl]
set overlay_helper [file join $script_dir lora_overlay_injection.tcl]
set reference_mem [file normalize [file join $repo_root fpga rom lora_sf7_l8_reference_q10.mem]]

foreach required_file [list $vendor_shell_bd $overlay_helper $reference_mem] {
  if {![file exists $required_file]} {
    error "Missing CLG400 integration input: $required_file"
  }
}

source $vendor_shell_bd
source $overlay_helper
lora_clg400_apply_overlay $reference_mem
