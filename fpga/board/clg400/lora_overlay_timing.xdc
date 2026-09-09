# The PS AXI/gpreg clock is asynchronous to the AD9361 receive clock family.
set ctrl_async_clks [get_clocks -quiet {clk_fpga_0}]
set sample_async_clks [get_clocks -quiet -include_generated_clocks {rx_clk}]
if {[llength $ctrl_async_clks] > 0 && [llength $sample_async_clks] > 0} {
  set_clock_groups -asynchronous \
    -group $ctrl_async_clks \
    -group $sample_async_clks
}

# The PS7-generated constraint explicitly says FCLK0 and FCLK1 are
# asynchronous and leaves the relationship to the user. FCLK0 clocks the AXI
# control plane; FCLK1 is the independent 200 MHz board/reference domain.
set ps_fclk0 [get_clocks -quiet {clk_fpga_0}]
set ps_fclk1 [get_clocks -quiet {clk_fpga_1}]
if {[llength $ps_fclk0] > 0 && [llength $ps_fclk1] > 0} {
  set_clock_groups -asynchronous \
    -group $ps_fclk0 \
    -group $ps_fclk1
}

# Mailbox request/acknowledge synchronizers. The 128-bit payload is held stable
# by protocol until the destination acknowledges the synchronized toggle.
set mailbox_first_stages [get_pins -hier -quiet -filter { \
  NAME =~ *lora_clg400_bridge/event_request_meta_reg/D || \
  NAME =~ *lora_clg400_bridge/event_ack_meta_reg/D || \
  NAME =~ *lora_clg400_bridge/ctrl_sample_meta_reg*/D || \
  NAME =~ *lora_clg400_bridge/status_meta_reg*/D}]
if {[llength $mailbox_first_stages] > 0} {
  set_false_path -to $mailbox_first_stages
}

# The receiver runs on a fixed PL clock, not the AD9361 divided data clock.
# That clock is made by an MMCM fed from the AXI control clock, so Vivado
# relates the two, but every path between them is either a two-flop
# synchronizer or a Gray-coded FIFO pointer. It is asynchronous to the AD9361
# receive family for the same reason. Grouping it explicitly keeps the existing
# false paths meaningful instead of leaving the crossings to be timed.
# Find it by the pin it drives, then by the MMCM that makes it. If neither
# works the crossings would be timed as if they were synchronous, which
# either fails implementation or, worse, passes with the CDC unconstrained.
# Stop instead: a missing constraint here is not something to discover on
# the bench.
set lora_receiver_clks [get_clocks -quiet -of_objects \
  [get_pins -quiet -hier -filter {NAME =~ *lora_clg400_bridge/sample_clk}]]
if {[llength $lora_receiver_clks] == 0} {
  set lora_receiver_clks [get_clocks -quiet -of_objects \
    [get_pins -quiet -hier -filter {NAME =~ *lora_receiver_clk*/clk_out1}]]
}
if {[llength $lora_receiver_clks] == 0} {
  set lora_receiver_clks [get_clocks -quiet {*lora_receiver_clk*}]
}
if {[llength $lora_receiver_clks] == 0} {
  error "lora_overlay_timing: cannot find the fixed receiver clock; the\
 sample-domain crossings would be left unconstrained"
}
puts "LORA_RECEIVER_CLOCK: $lora_receiver_clks"
if {[llength $ctrl_async_clks] > 0} {
  set_clock_groups -asynchronous \
    -group $lora_receiver_clks \
    -group $ctrl_async_clks
}
if {[llength $sample_async_clks] > 0} {
  set_clock_groups -asynchronous \
    -group $lora_receiver_clks \
    -group $sample_async_clks
}
