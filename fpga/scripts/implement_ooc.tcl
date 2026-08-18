# Place, route, timing, utilization, and vectorless power for one generated DUT.
#
# Boundary registers live in a target-specific wrapper so every functional
# input and output is timed register-to-register. The design remains
# out-of-context: no package pins, PS, board clocking, or AXI are invented.
#
# vivado -mode batch -source implement_ooc.tcl -tclargs \
#   <srcDir> <wrapperFile> <top> <generatedTop> <generatedMacro> <part> \
#   <probePeriodNs> <powerClockMHz> <inputTogglePercent> <junctionTempC> <outFile>
#
# generatedTop is the ModulePrefix-aware core top. generatedMacro is the
# wrapper macro used at the instantiation site. Historical generated snapshots
# used module DUT; the script falls back to that name so old measurements stay
# reproducible until HDL is regenerated.

if {$argc != 11} {
    puts "ERROR expected 11 arguments, got $argc"
    exit 1
}
set srcDir            [lindex $argv 0]
set wrapperFile       [lindex $argv 1]
set top               [lindex $argv 2]
set generatedTop      [lindex $argv 3]
set generatedMacro    [lindex $argv 4]
set part              [lindex $argv 5]
set probePeriod       [lindex $argv 6]
set powerClockMHz     [lindex $argv 7]
set inputToggle       [lindex $argv 8]
set junctionTemp      [lindex $argv 9]
set outFile           [lindex $argv 10]

set files [glob -nocomplain -directory $srcDir *.v]
if {[llength $files] == 0} {
    puts "ERROR no Verilog in $srcDir"
    exit 1
}
if {![file exists $wrapperFile]} {
    puts "ERROR wrapper not found: $wrapperFile"
    exit 1
}
if {$powerClockMHz <= 0 || $probePeriod <= 0} {
    puts "ERROR clock frequencies and periods must be positive"
    exit 1
}

proc module_exists {files moduleName} {
    set pattern [format {(?m)^\s*module\s+%s(?:\s|\(|#)} $moduleName]
    foreach path $files {
        set fh [open $path r]
        set text [read $fh]
        close $fh
        if {[regexp $pattern $text]} {
            return 1
        }
    }
    return 0
}

if {[module_exists $files $generatedTop]} {
    set generatedDut $generatedTop
} elseif {[module_exists $files DUT]} {
    set generatedDut DUT
    puts "INFO preferred generated top $generatedTop not found; using historical DUT"
} else {
    puts "ERROR neither generated top $generatedTop nor historical DUT exists"
    exit 1
}

set reportDir [file dirname $outFile]
file mkdir $reportDir

create_project -in_memory -part $part
add_files $files
add_files $wrapperFile
set_property verilog_define "${generatedMacro}=${generatedDut}" [current_fileset]
set_property top $top [current_fileset]

set xdc [file join $reportDir implement_ooc_probe.xdc]
set fh [open $xdc w]
puts $fh "create_clock -name clk -period $probePeriod \[get_ports clk\]"
puts $fh "set_property HD.CLK_SRC BUFGCTRL_X0Y0 \[get_ports clk\]"
close $fh
read_xdc $xdc

synth_design -top $top -part $part -mode out_of_context \
    -flatten_hierarchy rebuilt
opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force [file join $reportDir routed.dcp]
set routeStatus [report_route_status -return_string]
set fh [open [file join $reportDir route-status.rpt] w]
puts $fh $routeStatus
close $fh
set routeComplete [regexp {# of nets with routing errors\.+\s*:\s*0\s*:} $routeStatus]
report_timing_summary -delay_type min_max -max_paths 10 \
    -file [file join $reportDir timing-summary.rpt]
report_utilization -file [file join $reportDir utilization.rpt]

proc cell_count {report row} {
    set pattern "\\|\\s+${row}\\S*\\s+\\|\\s+(\\d+)\\s+\\|"
    if {[regexp $pattern $report -> value]} {
        return $value
    }
    return -1
}

proc worst_slack {delayType} {
    set paths [get_timing_paths -max_paths 1 -nworst 1 \
        -delay_type $delayType -quiet]
    if {[llength $paths] == 0} {
        return nan
    }
    set value [get_property SLACK [lindex $paths 0]]
    if {![string is double -strict $value]} {
        return nan
    }
    return $value
}

proc xml_report_number {report label} {
    set escaped [regsub -all {([][(){}.*+?$^\\|])} $label {\\\1}]
    set pattern [format {contents="%s"[^>]*/>\s*<tablecell[^>]*contents="([0-9]+(?:\.[0-9]+)?)"} $escaped]
    if {[regexp $pattern $report -> value]} {
        return $value
    }
    return nan
}

set util [report_utilization -return_string]
set luts  [cell_count $util "Slice LUTs"]
set regs  [cell_count $util "Slice Registers"]
set bram  [cell_count $util "Block RAM Tile"]
set dsp   [cell_count $util "DSPs"]
set carry [cell_count $util "CARRY4"]

set setupWns [worst_slack max]
set holdWns  [worst_slack min]
set criticalPath [lindex [get_timing_paths -max_paths 1 -nworst 1 \
    -delay_type max -quiet] 0]
set criticalStart [get_property STARTPOINT_PIN $criticalPath]
set criticalEnd [get_property ENDPOINT_PIN $criticalPath]
set criticalDataDelay [get_property DATAPATH_DELAY $criticalPath]
set criticalLogicDelay [get_property DATAPATH_LOGIC_DELAY $criticalPath]
set criticalNetDelay [get_property DATAPATH_NET_DELAY $criticalPath]
if {[string is double -strict $setupWns]} {
    set achieved [expr {$probePeriod - $setupWns}]
    if {$achieved > 0} {
        set fmax [expr {1000.0 / $achieved}]
    } else {
        set fmax nan
    }
} else {
    set achieved nan
    set fmax nan
}

# Timing is measured against the aggressive probe above. Power is reported at
# the maximum application sample clock (4 MHz by default), not at 200 MHz.
set powerPeriod [expr {1000.0 / $powerClockMHz}]
create_clock -name clk -period $powerPeriod [get_ports clk]

set_switching_activity -default_toggle_rate $inputToggle
set_switching_activity -default_static_probability 0.5
set_switching_activity -deassert_resets
set_operating_conditions -process typical -junction_temp $junctionTemp

set powerXml [file join $reportDir power.xml]
report_power -format xml -file $powerXml
report_power -advisory -file [file join $reportDir power.rpt]
set fh [open $powerXml r]
set power [read $fh]
close $fh
set totalPower   [xml_report_number $power "Total On-Chip Power (W)"]
set dynamicPower [xml_report_number $power "Dynamic (W)"]
set staticPower  [xml_report_number $power "Device Static (W)"]
set powerConfidenceMedium [regexp {contents="Confidence Level"[^>]*/>\s*<tablecell[^>]*contents="Medium"} $power]

set fh [open $outFile w]
puts $fh "part=$part"
puts $fh "generated_dut=$generatedDut"
puts $fh "probe_period_ns=$probePeriod"
puts $fh "power_clock_mhz=$powerClockMHz"
puts $fh "input_toggle_percent=$inputToggle"
puts $fh "junction_temp_c=$junctionTemp"
puts $fh "route_complete=$routeComplete"
puts $fh "luts=$luts"
puts $fh "registers=$regs"
puts $fh "bram_tiles=$bram"
puts $fh "dsps=$dsp"
puts $fh "carry4=$carry"
puts $fh "setup_wns_ns=$setupWns"
puts $fh "hold_wns_ns=$holdWns"
puts $fh "achieved_period_ns=$achieved"
puts $fh "fmax_mhz=$fmax"
puts $fh "critical_datapath_delay_ns=$criticalDataDelay"
puts $fh "critical_logic_delay_ns=$criticalLogicDelay"
puts $fh "critical_net_delay_ns=$criticalNetDelay"
puts $fh "critical_startpoint=$criticalStart"
puts $fh "critical_endpoint=$criticalEnd"
puts $fh "total_on_chip_power_w=$totalPower"
puts $fh "dynamic_power_w=$dynamicPower"
puts $fh "device_static_power_w=$staticPower"
puts $fh "power_report_resolution_w=0.001"
puts $fh "power_confidence_medium=$powerConfidenceMedium"
close $fh

puts "IMPLEMENT_OK top=$top generated=$generatedDut luts=$luts regs=$regs fmax=$fmax power=$totalPower"
exit 0
