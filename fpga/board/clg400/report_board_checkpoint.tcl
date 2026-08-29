set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir "../../.."]]
set project_root [file join $repo_root fpga build clg400-board]
set checkpoint_path [file join $project_root \
  lora_receiver_clg400.runs synth_1 system_top.dcp]
set report_dir [file join $project_root reports]

if {![file exists $checkpoint_path]} {
  puts "ERROR: missing synthesized checkpoint $checkpoint_path"
  exit 2
}

file mkdir $report_dir
open_checkpoint $checkpoint_path

# Clocks from the top-level and PS7 XDC files are implementation-only and are
# not retained as clock objects by a standalone post-synthesis checkpoint.
# Recreate the three authoritative roots before deriving generated clocks.
set rx_clk_port [get_ports -quiet rx_clk_in_p]
set ps_fclk0_pin [get_pins -quiet \
  {i_system_wrapper/system_i/sys_ps7/inst/PS7_i/FCLKCLK[0]}]
set ps_fclk1_pin [get_pins -quiet \
  {i_system_wrapper/system_i/sys_ps7/inst/PS7_i/FCLKCLK[1]}]
foreach {clock_name clock_period clock_object} [list \
    rx_clk 4.000 $rx_clk_port \
    clk_fpga_0 10.000 $ps_fclk0_pin \
    clk_fpga_1 5.000 $ps_fclk1_pin] {
  if {[llength $clock_object] != 1} {
    puts "ERROR: expected one root object for $clock_name"
    exit 3
  }
  if {[llength [get_clocks -quiet $clock_name]] == 0} {
    create_clock -name $clock_name -period $clock_period $clock_object
  }
}
set_input_jitter clk_fpga_0 0.3
set_input_jitter clk_fpga_1 0.15

# Match synth_board.tcl: apply the overlay CDC policy explicitly because this
# checkpoint can also be recovered after a Windows Vivado run-launcher stall.
source [file join $script_dir lora_overlay_timing.xdc]

report_utilization -file [file join $report_dir post_synth_utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 \
  -file [file join $report_dir post_synth_timing_summary.rpt]
report_cdc -details \
  -file [file join $report_dir post_synth_cdc.rpt]
report_methodology \
  -file [file join $report_dir post_synth_methodology.rpt]

puts "Checkpoint reports: $report_dir"
