# Out-of-context synthesis of one generated DUT.
#
# Out-of-context on purpose: there is no board wrapper, no clocking, and no
# AXI yet, so anything else would be measuring parts of the design that do
# not exist. These numbers describe the DUT alone and will change once it is
# wrapped.
#
#   vivado -mode batch -source synth_ooc.tcl -tclargs <srcDir> <part> <period> <outFile>
#
# Emits key=value lines so the caller never has to parse a Vivado report.

if {$argc != 4} {
    puts "ERROR expected 4 arguments, got $argc"
    exit 1
}
set srcDir  [lindex $argv 0]
set part    [lindex $argv 1]
set period  [lindex $argv 2]
set outFile [lindex $argv 3]

set files [glob -nocomplain -directory $srcDir *.v]
if {[llength $files] == 0} {
    puts "ERROR no Verilog in $srcDir"
    exit 1
}

create_project -in_memory -part $part
add_files $files
set_property top DUT [current_fileset]

# The clock has to constrain synthesis, not be declared after it, or the
# tool optimises against no timing target and the slack means nothing. The
# period is a probe rather than a requirement: Fmax is derived from the
# slack against it.
set xdc [file join [file dirname $outFile] synth_ooc_probe.xdc]
set fh [open $xdc w]
puts $fh "create_clock -name clk -period $period \[get_ports clk\]"
close $fh
read_xdc $xdc

synth_design -top DUT -part $part -mode out_of_context

set util [report_utilization -return_string]

proc cell_count {report row} {
    # Rows look like: | Slice LUTs* | 1234 | 0 | ... |
    set pattern "\\|\\s+${row}\\S*\\s+\\|\\s+(\\d+)\\s+\\|"
    if {[regexp $pattern $report -> value]} {
        return $value
    }
    return -1
}

set luts    [cell_count $util "Slice LUTs"]
set regs    [cell_count $util "Slice Registers"]
set bram    [cell_count $util "Block RAM Tile"]
set dsp     [cell_count $util "DSPs"]
set carry   [cell_count $util "CARRY4"]

set paths [get_timing_paths -max_paths 1 -nworst 1 -setup -quiet]
set wns ""
if {[llength $paths] > 0} {
    set wns [get_property SLACK [lindex $paths 0]]
}

# A purely combinational DUT has no register-to-register path, so there is
# no slack against the probe clock and no Fmax to report. That is a property
# of the block, not a failed measurement, so it is recorded as nan rather
# than silently turned into a number.
if {$wns eq "" || ![string is double -strict $wns]} {
    set wns nan
    set achieved nan
    set fmax nan
} else {
    # Achieved period is the probe minus the slack; negative slack means the
    # design is slower than the probe, which is still a measurement.
    set achieved [expr {$period - $wns}]
    if {$achieved > 0} {
        set fmax [expr {1000.0 / $achieved}]
    } else {
        set fmax nan
    }
}

set fh [open $outFile w]
puts $fh "part=$part"
puts $fh "probe_period_ns=$period"
puts $fh "luts=$luts"
puts $fh "registers=$regs"
puts $fh "bram_tiles=$bram"
puts $fh "dsps=$dsp"
puts $fh "carry4=$carry"
puts $fh "wns_ns=$wns"
puts $fh "achieved_period_ns=$achieved"
puts $fh "fmax_mhz=$fmax"
close $fh

puts "SYNTH_OK luts=$luts regs=$regs bram=$bram dsp=$dsp fmax=$fmax"
exit 0
