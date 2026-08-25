`timescale 1ns/1ps

// Sequence a short packet-rate matched-filter search around one coarse ToA.
//
// The controller reuses lora_matched_filter_mac for every integer candidate
// lag and feeds the resulting correlation-power stream directly into
// lora_peak_triplet_capture. This keeps the long complex matched filter
// packet-rate instead of building a continuous REF_SAMPLES-tap FIR.
//
// For SEARCH_RADIUS=8 the candidate window is
//
//   coarse_start_count-8 ... coarse_start_count ... coarse_start_count+8
//
// and therefore contains 17 integer lags. The peak-capture output is already
// expressed in the same absolute accepted-sample-count epoch as the IQ history
// buffer, so peak_sample_count is the integer-refined ToA for the later
// fractional interpolator.
//
// The reference coefficient interface is passed through from the reused MAC.
// A future SF7/L=8 reference ROM can therefore be attached without changing
// the search controller.
module lora_matched_filter_search #(
    parameter integer REF_SAMPLES   = 1024,
    parameter integer SEARCH_RADIUS = 8,
    parameter integer ACC_WIDTH     = 48,
    parameter integer POWER_SHIFT   = 30
) (
    input  wire                         clk,
    input  wire                         resetn,
    input  wire                         stream_reset,

    input  wire                         start,
    input  wire [63:0]                  coarse_start_count,

    output wire                         iq_read_req,
    output wire [63:0]                  iq_read_sample_count,
    input  wire signed [15:0]           iq_read_re,
    input  wire signed [15:0]           iq_read_im,
    input  wire [63:0]                  iq_read_sample_count_out,
    input  wire                         iq_read_valid,
    input  wire                         iq_read_miss,

    output wire [15:0]                  reference_index,
    input  wire signed [15:0]           reference_re,
    input  wire signed [15:0]           reference_im,

    output reg                          busy,
    output wire [63:0]                  search_first_count,

    output wire [31:0]                  correlation_magnitude,
    output wire                         correlation_magnitude_valid,
    output wire [63:0]                  correlation_sample_count,

    output wire [31:0]                  magnitude_before,
    output wire [31:0]                  magnitude_peak,
    output wire [31:0]                  magnitude_after,
    output wire [15:0]                  peak_index,
    output wire [63:0]                  peak_sample_count,
    output wire                         triplet_valid,

    output reg                          underflow_error,
    output reg                          search_restart_error,
    output reg                          mac_window_mismatch_error,
    output wire                         mac_read_miss_error,
    output wire                         mac_response_mismatch_error,
    output wire                         mac_restart_error,
    output wire                         peak_boundary_error,
    output wire                         peak_restart_error
);

    localparam integer SEARCH_LAGS = 2*SEARCH_RADIUS + 1;
    localparam [63:0] SEARCH_RADIUS_U64 = SEARCH_RADIUS;

    localparam [2:0] STATE_IDLE      = 3'd0;
    localparam [2:0] STATE_ARM_PEAK  = 3'd1;
    localparam [2:0] STATE_LAUNCH    = 3'd2;
    localparam [2:0] STATE_WAIT_MAC  = 3'd3;
    localparam [2:0] STATE_WAIT_PEAK = 3'd4;

    reg [2:0] state;
    reg [63:0] first_count_reg;
    reg [15:0] lag_index;

    wire mac_start = (state == STATE_LAUNCH);
    wire [63:0] mac_window_start_count = first_count_reg + lag_index;
    wire mac_busy;
    wire mac_result_valid;
    wire [63:0] mac_result_sample_count;
    wire signed [ACC_WIDTH-1:0] mac_correlation_re_unused;
    wire signed [ACC_WIDTH-1:0] mac_correlation_im_unused;
    wire [31:0] mac_correlation_power;

    wire peak_search_start = (state == STATE_ARM_PEAK);
    wire peak_busy_unused;

    assign search_first_count = first_count_reg;
    assign correlation_magnitude = mac_correlation_power;
    assign correlation_magnitude_valid = mac_result_valid;
    assign correlation_sample_count = mac_result_sample_count;

    initial begin
        if (SEARCH_RADIUS < 1 || SEARCH_RADIUS > 32767)
            $error("lora_matched_filter_search SEARCH_RADIUS must be 1..32767");
        if (SEARCH_LAGS > 65535)
            $error("lora_matched_filter_search search window exceeds 16-bit peak index");
    end

    lora_matched_filter_mac #(
        .REF_SAMPLES(REF_SAMPLES),
        .ACC_WIDTH(ACC_WIDTH),
        .POWER_SHIFT(POWER_SHIFT)
    ) u_mac (
        .clk(clk),
        .resetn(resetn),
        .stream_reset(stream_reset),
        .start(mac_start),
        .window_start_count(mac_window_start_count),
        .iq_read_req(iq_read_req),
        .iq_read_sample_count(iq_read_sample_count),
        .iq_read_re(iq_read_re),
        .iq_read_im(iq_read_im),
        .iq_read_sample_count_out(iq_read_sample_count_out),
        .iq_read_valid(iq_read_valid),
        .iq_read_miss(iq_read_miss),
        .reference_index(reference_index),
        .reference_re(reference_re),
        .reference_im(reference_im),
        .busy(mac_busy),
        .result_valid(mac_result_valid),
        .result_sample_count(mac_result_sample_count),
        .correlation_re(mac_correlation_re_unused),
        .correlation_im(mac_correlation_im_unused),
        .correlation_power(mac_correlation_power),
        .read_miss_error(mac_read_miss_error),
        .response_mismatch_error(mac_response_mismatch_error),
        .restart_error(mac_restart_error)
    );

    lora_peak_triplet_capture #(
        .SEARCH_SAMPLES(SEARCH_LAGS)
    ) u_peak_capture (
        .clk(clk),
        .resetn(resetn && !stream_reset),
        .search_start(peak_search_start),
        .search_base_count(first_count_reg),
        .magnitude(mac_correlation_power),
        .magnitude_valid(mac_result_valid),
        .magnitude_before(magnitude_before),
        .magnitude_peak(magnitude_peak),
        .magnitude_after(magnitude_after),
        .peak_index(peak_index),
        .peak_sample_count(peak_sample_count),
        .triplet_valid(triplet_valid),
        .busy(peak_busy_unused),
        .boundary_error(peak_boundary_error),
        .restart_error(peak_restart_error)
    );

    always @(posedge clk) begin
        if (!resetn || stream_reset) begin
            state                     <= STATE_IDLE;
            first_count_reg           <= 64'd0;
            lag_index                 <= 16'd0;
            busy                      <= 1'b0;
            underflow_error           <= 1'b0;
            search_restart_error      <= 1'b0;
            mac_window_mismatch_error <= 1'b0;
        end else begin
            underflow_error           <= 1'b0;
            search_restart_error      <= 1'b0;
            mac_window_mismatch_error <= 1'b0;

            if (start && busy)
                search_restart_error <= 1'b1;

            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        if (coarse_start_count < SEARCH_RADIUS_U64) begin
                            underflow_error <= 1'b1;
                        end else begin
                            first_count_reg <= coarse_start_count - SEARCH_RADIUS_U64;
                            lag_index       <= 16'd0;
                            busy            <= 1'b1;
                            state           <= STATE_ARM_PEAK;
                        end
                    end
                end

                STATE_ARM_PEAK: begin
                    // Give the peak-capture block one cycle to arm before the
                    // first long MAC result can arrive.
                    state <= STATE_LAUNCH;
                end

                STATE_LAUNCH: begin
                    // mac_start is combinationally asserted for this state.
                    state <= STATE_WAIT_MAC;
                end

                STATE_WAIT_MAC: begin
                    if (mac_read_miss_error || mac_response_mismatch_error ||
                        mac_restart_error) begin
                        busy  <= 1'b0;
                        state <= STATE_IDLE;
                    end else if (mac_result_valid) begin
                        if (mac_result_sample_count != mac_window_start_count) begin
                            mac_window_mismatch_error <= 1'b1;
                            busy                      <= 1'b0;
                            state                     <= STATE_IDLE;
                        end else if (lag_index == SEARCH_LAGS-1) begin
                            state <= STATE_WAIT_PEAK;
                        end else begin
                            lag_index <= lag_index + 16'd1;
                            state     <= STATE_LAUNCH;
                        end
                    end
                end

                STATE_WAIT_PEAK: begin
                    if (triplet_valid || peak_boundary_error || peak_restart_error) begin
                        busy  <= 1'b0;
                        state <= STATE_IDLE;
                    end
                end

                default: begin
                    busy  <= 1'b0;
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
