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
