`timescale 1ns/1ps

// Retain a recent accepted-sample IQ history for packet-rate ToA refinement.
//
// The future matched-filter search engine runs only after coarse acquisition,
// so keeping a circular IQ history is substantially cheaper than evaluating a
// long matched filter continuously at the sample rate.
//
// Contract:
//   * one complex sample is stored for every asserted sample_valid cycle;
//   * next_sample_count is the absolute accepted-sample index of the next write;
//   * oldest_sample_count is the oldest absolute index still retained;
//   * samples_retained saturates at DEPTH;
//   * read_sample_count addresses samples by absolute accepted-sample index,
//     not by physical RAM address;
//   * read_valid/read_miss are registered one-cycle response pulses;
//   * a request outside the retained interval [oldest, next) pulses read_miss;
//   * a read colliding with the physical write address is rejected rather than
//     depending on vendor-specific read-during-write BRAM behaviour;
//   * stream_reset restarts the accepted-sample epoch so this buffer stays
//     aligned with the generated FFT correlator's symbolSampleCount semantics.
//
// DEPTH must be a power of two. The production SF7/L=8 receiver uses 65536
// samples (2 MiBit for complex 16+16-bit IQ). The history must cover not only
// detector latency and the 1024-sample correlation window, but also samples
// accepted while the reused two-cycle MAC evaluates all 17 lags. A stopped-
// stream regression hid this live-window requirement when the depth was 16384.
module lora_iq_history_buffer #(
    parameter integer DEPTH = 16384
) (
    input  wire                    clk,
    input  wire                    resetn,
    input  wire                    stream_reset,

    input  wire signed [15:0]      iq_in_re,
    input  wire signed [15:0]      iq_in_im,
    input  wire                    sample_valid,

    input  wire                    read_req,
    input  wire [63:0]             read_sample_count,
    output wire signed [15:0]      read_iq_re,
    output wire signed [15:0]      read_iq_im,
    output reg  [63:0]             read_sample_count_out,
    output reg                     read_valid,
    output reg                     read_miss,

    output reg  [63:0]             next_sample_count,
    output reg  [63:0]             oldest_sample_count,
    output reg  [31:0]             samples_retained
);

    localparam integer ADDR_WIDTH = $clog2(DEPTH);

    // A packed complex word maps naturally to one simple dual-port RAM.
    (* ram_style = "block" *) reg [31:0] iq_mem [0:DEPTH-1];
    reg [31:0] read_iq_word;

    assign read_iq_re = read_iq_word[31:16];
    assign read_iq_im = read_iq_word[15:0];

    wire [ADDR_WIDTH-1:0] write_addr = next_sample_count[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] read_addr  = read_sample_count[ADDR_WIDTH-1:0];

    wire read_in_range = (samples_retained != 0) &&
                         (read_sample_count >= oldest_sample_count) &&
                         (read_sample_count < next_sample_count);

    // Avoid an implementation-dependent BRAM read-during-write result. This
    // matters when a full buffer overwrites the oldest retained sample.
    wire read_write_collision = sample_valid && (read_addr == write_addr);

    initial begin
        if (DEPTH < 2 || ((DEPTH & (DEPTH-1)) != 0))
            $error("lora_iq_history_buffer DEPTH must be a power of two >= 2");
    end

    // Keep the read and write ports in separate clocked processes. This is
    // the canonical Vivado simple-dual-port template; combining the ports in
    // one process caused the 16k x 32 history to be implemented as more than
    // 11k LUTRAMs despite ram_style="block".
    always @(posedge clk) begin
        if (!resetn || stream_reset) begin
            read_iq_word          <= 32'd0;
            read_sample_count_out <= 64'd0;
            read_valid            <= 1'b0;
            read_miss             <= 1'b0;
        end else begin
            read_valid <= 1'b0;
            read_miss  <= 1'b0;

            if (read_req) begin
                read_sample_count_out <= read_sample_count;
                if (read_in_range && !read_write_collision) begin
                    read_iq_word <= iq_mem[read_addr];
                    read_valid <= 1'b1;
                end else begin
                    read_miss <= 1'b1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!resetn || stream_reset) begin
            next_sample_count   <= 64'd0;
            oldest_sample_count <= 64'd0;
            samples_retained    <= 32'd0;
        end else begin
            if (sample_valid) begin
                iq_mem[write_addr] <= {iq_in_re, iq_in_im};
                next_sample_count  <= next_sample_count + 64'd1;

                if (samples_retained < DEPTH) begin
                    samples_retained <= samples_retained + 32'd1;
                end else begin
                    // Once full, every accepted sample evicts exactly one old
                    // sample while occupancy remains saturated.
                    oldest_sample_count <= oldest_sample_count + 64'd1;
                end
            end
        end
    end

endmodule
