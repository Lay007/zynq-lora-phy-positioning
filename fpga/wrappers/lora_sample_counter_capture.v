`timescale 1ns/1ps

// Free-running accepted-sample counter with explicit coarse timestamp capture.
//
// Semantics:
//   * sample_count increments once for every asserted sample_valid cycle;
//   * capture snapshots the number of accepted samples observed before the
//     current rising edge;
//   * if sample_valid and capture are asserted together, the captured value is
//     the pre-increment sample_count and sample_count then advances by one;
//   * capture_valid pulses for exactly one cycle for every capture pulse;
//   * synchronous active-low reset clears the live counter, snapshot and valid;
//   * wraparound is modulo 2**COUNTER_WIDTH and is intentional.
//
// The default width is 64 bits for the LoRa receiver PL timebase. The width is
// parameterized so wraparound can be exercised in a short self-checking test.
module lora_sample_counter_capture #(
    parameter integer COUNTER_WIDTH = 64
) (
    input  wire                         clk,
    input  wire                         resetn,
    input  wire                         sample_valid,
    input  wire                         capture,

    output reg  [COUNTER_WIDTH-1:0]     sample_count,
    output reg  [COUNTER_WIDTH-1:0]     captured_sample_count,
    output reg                          capture_valid
);

    always @(posedge clk) begin
        if (!resetn) begin
            sample_count          <= {COUNTER_WIDTH{1'b0}};
            captured_sample_count <= {COUNTER_WIDTH{1'b0}};
            capture_valid         <= 1'b0;
        end else begin
            capture_valid <= 1'b0;

            if (capture) begin
                captured_sample_count <= sample_count;
                capture_valid         <= 1'b1;
            end

            if (sample_valid)
                sample_count <= sample_count + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
        end
    end

endmodule
