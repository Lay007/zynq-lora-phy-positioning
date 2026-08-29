set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir "../../.."]]
set project_name "lora_receiver_clg400"
set project_root [file join $repo_root fpga build clg400-board]
set xpr_path [file join $project_root "${project_name}.xpr"]
set report_dir [file join $project_root reports]

if {![file exists $xpr_path]} {
  puts "ERROR: missing project $xpr_path; run system_project.tcl first."
  exit 2
}

file mkdir $report_dir
open_project $xpr_path
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS: $synth_status"
if {![string match "*Complete*" $synth_status]} {
  puts "ERROR: synthesis did not complete successfully."
  exit 3
}

open_run synth_1

# The CDC constraints are also installed as a pre-opt implementation hook.
# Source them explicitly here so the post-synthesis timing/CDC reports use the
# same clock-domain model before implementation is attempted.
source [file join $script_dir lora_overlay_timing.xdc]

report_utilization -file [file join $report_dir post_synth_utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 \
  -file [file join $report_dir post_synth_timing_summary.rpt]
report_cdc -details \
  -file [file join $report_dir post_synth_cdc.rpt]
report_methodology \
  -file [file join $report_dir post_synth_methodology.rpt]

puts "Synthesis reports: $report_dir"
