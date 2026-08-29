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
  # vendor sample domain to the util_clkdiv /4 leg (62.5 MHz at the 250 MHz XDC
  # maximum) so the ADI FIFO/DMA/DAC path and the LoRa receiver remain in one
  # clock domain. The run-time /2 leg is 125 MHz and the current generated FFT
  # does not close timing there. Do not paper over that with a broad multicycle.
  set divclk_sel_pin [get_bd_pins util_ad9361_divclk/clk_sel]
  set divclk_sel_net [get_bd_nets -quiet -of_objects $divclk_sel_pin]
  if {[llength $divclk_sel_net] != 1} {
    error "expected exactly one vendor util_ad9361_divclk/clk_sel net"
  }
  disconnect_bd_net $divclk_sel_net $divclk_sel_pin
  ad_connect GND util_ad9361_divclk/clk_sel

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
  ad_ip_parameter axi_gpreg_lora CONFIG.NUM_OF_CLK_MONS 0
  ad_connect sys_cpu_clk axi_gpreg_lora/s_axi_aclk
  ad_connect sys_cpu_resetn axi_gpreg_lora/s_axi_aresetn
  ad_cpu_interconnect 0x79040000 axi_gpreg_lora

  set lora_bridge [create_bd_cell -type module -reference lora_clg400_gpreg_bridge lora_clg400_bridge]
  set_property CONFIG.REFERENCE_FILE $reference_mem $lora_bridge
  ad_connect sys_cpu_clk lora_clg400_bridge/ctrl_clk
  ad_connect sys_cpu_resetn lora_clg400_bridge/ctrl_resetn
  ad_connect util_ad9361_divclk/clk_out lora_clg400_bridge/sample_clk
  ad_connect util_ad9361_divclk_reset/peripheral_aresetn lora_clg400_bridge/sample_resetn
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
