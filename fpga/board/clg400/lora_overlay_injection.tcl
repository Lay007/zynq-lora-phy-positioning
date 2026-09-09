# Add the LoRa timestamp receiver to the recovered CLG400 AD9361 vendor shell.
# The vendor block design and ADI helper procedures must already be loaded.

proc lora_clg400_apply_overlay {reference_mem} {
  # Match the hardware-qualified course reconstruction. The recovered vendor
  # Tcl carried a preset that otherwise restores the wrong MIO14/15 directions.
  set_property -dict [list \
    CONFIG.preset {None} \
    CONFIG.PCW_MIO_14_DIRECTION {in} \
    CONFIG.PCW_MIO_15_DIRECTION {out} \
  ] [get_bd_cells sys_ps7]

  # This image is intentionally a low-rate SF7/L=8 acquisition image. Pin the
  # vendor sample domain to the util_clkdiv /4 leg so the ADI FIFO/DMA/DAC path
  # stays in one clock domain. The run-time /2 leg does not close timing with
  # the current generated FFT. Do not paper over that with a broad multicycle.
  #
  # This leg is 62.5 MHz only at the 250 MHz XDC maximum, which is the AD9361
  # at 61.44 MS/s. The AD9361 data clock is four times the sample rate, so the
  # /4 leg equals the sample rate at every rate the part can be programmed to -
  # one fabric clock per sample, always. The receiver is no longer clocked from
  # it; see below.
  set divclk_sel_pin [get_bd_pins util_ad9361_divclk/clk_sel]
  set divclk_sel_net [get_bd_nets -quiet -of_objects $divclk_sel_pin]
  if {[llength $divclk_sel_net] != 1} {
    error "expected exactly one vendor util_ad9361_divclk/clk_sel net"
  }
  disconnect_bd_net $divclk_sel_net $divclk_sel_pin
  ad_connect GND util_ad9361_divclk/clk_sel

  # A fixed clock for the LoRa receiver.
  #
  # The joint up/down grid search costs about 135,000 clocks and has to finish
  # inside the 2304-sample SFD, so it needs roughly sixty clocks per sample.
  # util_ad9361_divclk/clk_out supplies one, which is why the search never
  # completed on the board: it was aborted by the history read window ageing
  # out some fifty symbols into the packet, long past the header. No choice of
  # AD9361 sample rate changes that ratio, so the receiver gets its own clock
  # and the samples cross into it.
  set lora_clk [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 lora_receiver_clk]
  set_property -dict [list \
    CONFIG.PRIM_SOURCE {Global_buffer} \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {62.500} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {false} \
  ] $lora_clk
  ad_connect sys_cpu_clk lora_receiver_clk/clk_in1

  set lora_rstgen [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 lora_receiver_reset]
  set_property -dict [list CONFIG.C_EXT_RST_WIDTH {1}] $lora_rstgen
  ad_connect lora_receiver_clk/clk_out1 lora_receiver_reset/slowest_sync_clk
  ad_connect sys_cpu_resetn lora_receiver_reset/ext_reset_in
  ad_connect lora_receiver_clk/locked lora_receiver_reset/dcm_locked

  # Extend the existing PS AXI-Lite fabric rather than recreating it.
  set existing_cpu_mi [get_property CONFIG.NUM_MI [get_bd_cells axi_cpu_interconnect]]
  if {$existing_cpu_mi ne ""} {
    set ::sys_cpu_interconnect_index $existing_cpu_mi
  }

  ad_ip_instance axi_gpreg axi_gpreg_lora
  # axi_gpreg declares ID as a long integer; Vivado 2021.1 rejects a Tcl hex
  # literal here even though the resulting 32-bit value is the ASCII "LORA".
  ad_ip_parameter axi_gpreg_lora CONFIG.ID 1280266817
  ad_ip_parameter axi_gpreg_lora CONFIG.NUM_OF_IO 8
  # Monitor 0 is the AD9361 divided data clock the receiver used to run on and
  # monitor 1 is the new fixed clock, whose frequency is known exactly. Reading
  # both makes the first an absolute measurement rather than an inference from
  # the divider setting.
  ad_ip_parameter axi_gpreg_lora CONFIG.NUM_OF_CLK_MONS 2
  ad_connect sys_cpu_clk axi_gpreg_lora/s_axi_aclk
  ad_connect sys_cpu_resetn axi_gpreg_lora/s_axi_aresetn
  ad_cpu_interconnect 0x79040000 axi_gpreg_lora
  ad_connect util_ad9361_divclk/clk_out axi_gpreg_lora/d_clk_0
  ad_connect lora_receiver_clk/clk_out1 axi_gpreg_lora/d_clk_1

  set lora_bridge [create_bd_cell -type module -reference lora_clg400_gpreg_bridge lora_clg400_bridge]
  set_property CONFIG.REFERENCE_FILE $reference_mem $lora_bridge
  ad_connect sys_cpu_clk lora_clg400_bridge/ctrl_clk
  ad_connect sys_cpu_resetn lora_clg400_bridge/ctrl_resetn
  ad_connect lora_receiver_clk/clk_out1 lora_clg400_bridge/sample_clk
  ad_connect lora_receiver_reset/peripheral_aresetn lora_clg400_bridge/sample_resetn
  # rx_clk carries only the arriving samples now; they cross inside the bridge.
  ad_connect util_ad9361_divclk/clk_out lora_clg400_bridge/rx_clk
  ad_connect util_ad9361_divclk_reset/peripheral_aresetn lora_clg400_bridge/rx_resetn
  ad_connect axi_gpreg_lora/up_gp_out_0 lora_clg400_bridge/gp_ctrl

  ad_connect lora_clg400_bridge/gp_status axi_gpreg_lora/up_gp_in_0
  ad_connect lora_clg400_bridge/gp_sequence axi_gpreg_lora/up_gp_in_1
  ad_connect lora_clg400_bridge/gp_coarse_lo axi_gpreg_lora/up_gp_in_2
  ad_connect lora_clg400_bridge/gp_coarse_hi axi_gpreg_lora/up_gp_in_3
  ad_connect lora_clg400_bridge/gp_fractional_q12 axi_gpreg_lora/up_gp_in_4
  ad_connect lora_clg400_bridge/gp_log_peak_q12 axi_gpreg_lora/up_gp_in_5
  ad_connect lora_clg400_bridge/gp_debug axi_gpreg_lora/up_gp_in_6
  ad_connect lora_clg400_bridge/gp_signature axi_gpreg_lora/up_gp_in_7

  # Consume the formatted FIFO stream, not the raw offset-binary ADC pins.
  # xlconcat places In0 in the least-significant bits, yielding
  # {valid, dout_data_0 (I), dout_data_1 (Q)} at the bridge.
  set rx_concat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 lora_rx_sample_concat]
  set_property -dict [list \
    CONFIG.NUM_PORTS {3} \
    CONFIG.IN0_WIDTH {16} \
    CONFIG.IN1_WIDTH {16} \
    CONFIG.IN2_WIDTH {1} \
  ] $rx_concat
  ad_connect util_ad9361_adc_fifo/dout_data_1 lora_rx_sample_concat/In0
  ad_connect util_ad9361_adc_fifo/dout_data_0 lora_rx_sample_concat/In1
  ad_connect util_ad9361_adc_fifo/dout_valid_0 lora_rx_sample_concat/In2
  ad_connect lora_rx_sample_concat/dout lora_clg400_bridge/rx_sample_bus
}
