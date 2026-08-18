// Boundary-register wrapper for physical implementation measurements.
//
// The generated DUT is kept untouched. Registering every functional input
// and output closes its external combinational paths so post-route timing is
// measured register-to-register. clk_enable is tied high because the
// correlator consumes one sample on every application clock.
//
// Older committed HDL used the generic module name DUT. New regeneration uses
// a target-specific ModulePrefix so several generated cores can coexist in one
// Vivado design. The implementation flow defines LORA_FFT_GENERATED_DUT to the
// prefixed name; the fallback keeps historical generated snapshots measurable.

`timescale 1 ns / 1 ns

`ifndef LORA_FFT_GENERATED_DUT
`define LORA_FFT_GENERATED_DUT DUT
`endif

module fft_correlator_route_top
          (clk,
           reset,
           iqIn_re,
           iqIn_im,
           validIn,
           resetIn,
           resyncValid,
           resyncSkip,
           ce_out,
           symbolIndex,
           symbolValid,
           confidence,
           peakMagnitudeSquared,
           spectrumSum,
           symbolBoundary,
           symbolSampleCount,
           timestampValid);

  input clk;
  input reset;
  input signed [15:0] iqIn_re;
  input signed [15:0] iqIn_im;
  input validIn;
  input resetIn;
  input resyncValid;
  input [31:0] resyncSkip;
  output reg ce_out;
  output reg [31:0] symbolIndex;
  output reg symbolValid;
  output reg [15:0] confidence;
  output reg [15:0] peakMagnitudeSquared;
  output reg [15:0] spectrumSum;
  output reg symbolBoundary;
  output reg [63:0] symbolSampleCount;
  output reg timestampValid;

  reg signed [15:0] iqIn_re_reg;
  reg signed [15:0] iqIn_im_reg;
  reg validIn_reg;
  reg resetIn_reg;
  reg resyncValid_reg;
  reg [31:0] resyncSkip_reg;

  wire dut_ce_out;
  wire [31:0] dut_symbolIndex;
  wire dut_symbolValid;
  wire [15:0] dut_confidence;
  wire [15:0] dut_peakMagnitudeSquared;
  wire [15:0] dut_spectrumSum;
  wire dut_symbolBoundary;
  wire [63:0] dut_symbolSampleCount;
  wire dut_timestampValid;

  `LORA_FFT_GENERATED_DUT u_dut
        (.clk(clk),
         .reset(reset),
         .clk_enable(1'b1),
         .iqIn_re(iqIn_re_reg),
         .iqIn_im(iqIn_im_reg),
         .validIn(validIn_reg),
         .resetIn(resetIn_reg),
         .resyncValid(resyncValid_reg),
         .resyncSkip(resyncSkip_reg),
         .ce_out(dut_ce_out),
         .symbolIndex(dut_symbolIndex),
         .symbolValid(dut_symbolValid),
         .confidence_1(dut_confidence),
         .peakMagnitudeSquared(dut_peakMagnitudeSquared),
         .spectrumSum(dut_spectrumSum),
         .symbolBoundary(dut_symbolBoundary),
         .symbolSampleCount(dut_symbolSampleCount),
         .timestampValid(dut_timestampValid));

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      iqIn_re_reg <= 16'sd0;
      iqIn_im_reg <= 16'sd0;
      validIn_reg <= 1'b0;
      resetIn_reg <= 1'b0;
      resyncValid_reg <= 1'b0;
      resyncSkip_reg <= 32'd0;
      ce_out <= 1'b0;
      symbolIndex <= 32'd0;
      symbolValid <= 1'b0;
      confidence <= 16'd0;
      peakMagnitudeSquared <= 16'd0;
      spectrumSum <= 16'd0;
      symbolBoundary <= 1'b0;
      symbolSampleCount <= 64'd0;
      timestampValid <= 1'b0;
    end
    else begin
      iqIn_re_reg <= iqIn_re;
      iqIn_im_reg <= iqIn_im;
      validIn_reg <= validIn;
      resetIn_reg <= resetIn;
      resyncValid_reg <= resyncValid;
      resyncSkip_reg <= resyncSkip;
      ce_out <= dut_ce_out;
      symbolIndex <= dut_symbolIndex;
      symbolValid <= dut_symbolValid;
      confidence <= dut_confidence;
      peakMagnitudeSquared <= dut_peakMagnitudeSquared;
      spectrumSum <= dut_spectrumSum;
      symbolBoundary <= dut_symbolBoundary;
      symbolSampleCount <= dut_symbolSampleCount;
      timestampValid <= dut_timestampValid;
    end
  end
endmodule
