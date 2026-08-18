`timescale 1ns/1ps

// Join the coarse PL timestamp and the packet-rate fractional ToA estimate
// into one atomic metadata record.
//
// Contract:
//   * one unmatched coarse fragment and one unmatched fractional fragment may
//     be outstanding;
//   * fragments may arrive in either order or in the same clock cycle;
//   * timestamp_valid pulses for one clock on the cycle after a complete pair
//     was present;
//   * duplicate unmatched fragments pulse metadata_overflow and do not
//     overwrite the first fragment;
//   * synchronous active-low reset discards a partial pair.
//
// fractional_toa_q12 uses the same units as the generated ToA interpolator:
// signed 1/4096 sample in a 32-bit container.
module lora_timestamp_metadata_join (
    input  wire                    clk,
    input  wire                    resetn,

    input  wire [63:0]             coarse_sample_count,
    input  wire                    coarse_valid,
    input  wire signed [31:0]      fractional_toa_q12,
    input  wire                    fractional_valid,

    output reg  [63:0]             timestamp_coarse,
    output reg  signed [31:0]      timestamp_fractional_q12,
    output reg                     timestamp_valid,
    output reg                     metadata_overflow
);

    reg [63:0]        coarse_reg;
    reg signed [31:0] fractional_reg;
    reg               coarse_pending;
    reg               fractional_pending;

    wire pair_ready = coarse_pending && fractional_pending;

    always @(posedge clk) begin
        if (!resetn) begin
            coarse_reg                <= 64'd0;
            fractional_reg            <= 32'sd0;
            coarse_pending            <= 1'b0;
            fractional_pending        <= 1'b0;
            timestamp_coarse          <= 64'd0;
            timestamp_fractional_q12  <= 32'sd0;
            timestamp_valid           <= 1'b0;
            metadata_overflow         <= 1'b0;
        end else begin
            timestamp_valid   <= 1'b0;
            metadata_overflow <= 1'b0;

            // Emit an already-complete pair. Nonblocking assignment ordering
            // below intentionally allows the first fragment of the next pair
            // to be accepted in the same cycle as this emission.
            if (pair_ready) begin
                timestamp_coarse         <= coarse_reg;
                timestamp_fractional_q12 <= fractional_reg;
                timestamp_valid          <= 1'b1;
                coarse_pending           <= 1'b0;
                fractional_pending       <= 1'b0;
            end

            if (coarse_valid) begin
                if (coarse_pending && !pair_ready) begin
                    metadata_overflow <= 1'b1;
                end else begin
                    coarse_reg     <= coarse_sample_count;
                    coarse_pending <= 1'b1;
                end
            end

            if (fractional_valid) begin
                if (fractional_pending && !pair_ready) begin
                    metadata_overflow <= 1'b1;
                end else begin
                    fractional_reg     <= fractional_toa_q12;
                    fractional_pending <= 1'b1;
                end
            end
        end
    end

endmodule
