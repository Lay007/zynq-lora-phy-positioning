// Boundary-register wrapper for physical implementation measurements.
//
// The packet-rate DUT is left unchanged. Boundary registers make all
// external combinational paths part of the post-route timing measurement.
//
// Older committed HDL used the generic module name DUT. New regeneration uses
// a target-specific ModulePrefix so several generated cores can coexist in one
// Vivado design. The implementation flow defines LORA_TOA_GENERATED_DUT to the
// prefixed name; the fallback keeps historical generated snapshots measurable.

`timescale 1 ns / 1 ns

`ifndef LORA_TOA_GENERATED_DUT
`define LORA_TOA_GENERATED_DUT DUT
`endif

module toa_interpolator_route_top
          (clk,
           reset,
           magnitudeBefore,
           magnitudePeak,
           magnitudeAfter,
           tripletValid,
           ce_out,
           offsetSamples,
           offsetValid,
           logPeak);

  input clk;
  input reset;
  input [31:0] magnitudeBefore;
  input [31:0] magnitudePeak;
  input [31:0] magnitudeAfter;
  input tripletValid;
  output reg ce_out;
  output reg signed [31:0] offsetSamples;
  output reg offsetValid;
  output reg signed [31:0] logPeak;

  reg [31:0] magnitudeBefore_reg;
  reg [31:0] magnitudePeak_reg;
  reg [31:0] magnitudeAfter_reg;
  reg tripletValid_reg;

  wire dut_ce_out;
  wire signed [31:0] dut_offsetSamples;
  wire dut_offsetValid;
  wire signed [31:0] dut_logPeak;

  `LORA_TOA_GENERATED_DUT u_dut
        (.clk(clk),
         .reset(reset),
         .clk_enable(1'b1),
         .magnitudeBefore(magnitudeBefore_reg),
         .magnitudePeak(magnitudePeak_reg),
         .magnitudeAfter(magnitudeAfter_reg),
         .tripletValid(tripletValid_reg),
         .ce_out(dut_ce_out),
         .offsetSamples(dut_offsetSamples),
         .offsetValid(dut_offsetValid),
         .logPeak(dut_logPeak));

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      magnitudeBefore_reg <= 32'd0;
      magnitudePeak_reg <= 32'd0;
      magnitudeAfter_reg <= 32'd0;
      tripletValid_reg <= 1'b0;
      ce_out <= 1'b0;
      offsetSamples <= 32'sd0;
      offsetValid <= 1'b0;
      logPeak <= 32'sd0;
    end
    else begin
      magnitudeBefore_reg <= magnitudeBefore;
      magnitudePeak_reg <= magnitudePeak;
      magnitudeAfter_reg <= magnitudeAfter;
      tripletValid_reg <= tripletValid;
      ce_out <= dut_ce_out;
      offsetSamples <= dut_offsetSamples;
      offsetValid <= dut_offsetValid;
      logPeak <= dut_logPeak;
    end
  end
endmodule
