`timescale 1ns/1ps

module tb_lora_matched_filter_search_sf7_l8;
    localparam integer REF_SAMPLES = 1024;
    localparam integer SEARCH_RADIUS = 8;
    localparam integer SEARCH_LAGS = 17;
    localparam integer STIMULUS_SAMPLES = REF_SAMPLES + 2*SEARCH_RADIUS;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg resetn = 1'b0;
    reg stream_reset = 1'b0;
    reg signed [15:0] iq_in_re = 16'sd0;
    reg signed [15:0] iq_in_im = 16'sd0;
    reg sample_valid = 1'b0;
    reg search_start = 1'b0;

    reg [31:0] stimulus [0:STIMULUS_SAMPLES-1];
    reg [31:0] expected_power [0:SEARCH_LAGS-1];

    wire iq_read_req;
    wire [63:0] iq_read_sample_count;
    wire signed [15:0] iq_read_re;
    wire signed [15:0] iq_read_im;
    wire [63:0] iq_read_sample_count_out;
    wire iq_read_valid;
    wire iq_read_miss;
    wire [15:0] reference_index;
    wire signed [15:0] reference_re;
    wire signed [15:0] reference_im;
    wire search_busy;
    wire [63:0] search_first_count;
    wire [31:0] correlation_magnitude;
    wire correlation_magnitude_valid;
    wire [63:0] correlation_sample_count;
    wire [31:0] magnitude_before;
    wire [31:0] magnitude_peak;
    wire [31:0] magnitude_after;
    wire [15:0] peak_index;
    wire [63:0] peak_sample_count;
    wire triplet_valid;
    wire underflow_error;
    wire search_restart_error;
    wire mac_window_mismatch_error;
    wire mac_read_miss_error;
    wire mac_response_mismatch_error;
    wire mac_restart_error;
    wire peak_boundary_error;
    wire peak_restart_error;

    integer errors = 0;
    integer sample_index;
    integer correlation_seen = 0;
    integer triplet_seen = 0;
    integer timeout_cycles = 0;

    lora_iq_history_buffer #(.DEPTH(2048)) u_history (
        .clk(clk), .resetn(resetn), .stream_reset(stream_reset),
        .iq_in_re(iq_in_re), .iq_in_im(iq_in_im), .sample_valid(sample_valid),
        .read_req(iq_read_req), .read_sample_count(iq_read_sample_count),
        .read_iq_re(iq_read_re), .read_iq_im(iq_read_im),
        .read_sample_count_out(iq_read_sample_count_out),
        .read_valid(iq_read_valid), .read_miss(iq_read_miss),
        .next_sample_count(), .oldest_sample_count(), .samples_retained()
    );

    lora_reference_chirp_rom u_reference (
        .reference_index(reference_index),
        .reference_re(reference_re), .reference_im(reference_im)
    );

    lora_matched_filter_search #(
        .REF_SAMPLES(REF_SAMPLES), .SEARCH_RADIUS(SEARCH_RADIUS),
        .ACC_WIDTH(48), .POWER_SHIFT(30)
    ) dut (
        .clk(clk), .resetn(resetn), .stream_reset(stream_reset),
        .start(search_start), .coarse_start_count(64'd8),
        .iq_read_req(iq_read_req), .iq_read_sample_count(iq_read_sample_count),
        .iq_read_re(iq_read_re), .iq_read_im(iq_read_im),
        .iq_read_sample_count_out(iq_read_sample_count_out),
        .iq_read_valid(iq_read_valid), .iq_read_miss(iq_read_miss),
        .reference_index(reference_index), .reference_re(reference_re),
        .reference_im(reference_im), .busy(search_busy),
        .search_first_count(search_first_count),
        .correlation_magnitude(correlation_magnitude),
        .correlation_magnitude_valid(correlation_magnitude_valid),
        .correlation_sample_count(correlation_sample_count),
        .magnitude_before(magnitude_before), .magnitude_peak(magnitude_peak),
        .magnitude_after(magnitude_after), .peak_index(peak_index),
        .peak_sample_count(peak_sample_count), .triplet_valid(triplet_valid),
        .underflow_error(underflow_error),
        .search_restart_error(search_restart_error),
        .mac_window_mismatch_error(mac_window_mismatch_error),
        .mac_read_miss_error(mac_read_miss_error),
        .mac_response_mismatch_error(mac_response_mismatch_error),
        .mac_restart_error(mac_restart_error),
        .peak_boundary_error(peak_boundary_error),
        .peak_restart_error(peak_restart_error)
    );

    always @(posedge clk) begin
        #1;
        if (resetn) begin
            if (correlation_magnitude_valid) begin
                if (correlation_seen >= SEARCH_LAGS) begin
                    errors = errors + 1;
                    $display("FAIL unexpected extra correlation result");
                end else begin
                    if (correlation_sample_count !== correlation_seen) begin
                        errors = errors + 1;
                        $display("FAIL correlation[%0d] count got=%0d", correlation_seen,
                                 correlation_sample_count);
                    end
                    if (correlation_magnitude !== expected_power[correlation_seen]) begin
                        errors = errors + 1;
                        $display("FAIL correlation[%0d] power got=%0d expected=%0d",
                                 correlation_seen, correlation_magnitude,
                                 expected_power[correlation_seen]);
                    end
                end
                correlation_seen = correlation_seen + 1;
            end

            if (triplet_valid) begin
                triplet_seen = triplet_seen + 1;
                if (peak_index !== 16'd8 || peak_sample_count !== 64'd8 ||
                    magnitude_before !== expected_power[7] ||
                    magnitude_peak !== expected_power[8] ||
                    magnitude_after !== expected_power[9]) begin
                    errors = errors + 1;
                    $display("FAIL full-size peak/triplet mismatch index=%0d count=%0d",
                             peak_index, peak_sample_count);
                end
            end

            if (underflow_error || search_restart_error ||
                mac_window_mismatch_error || mac_read_miss_error ||
                mac_response_mismatch_error || mac_restart_error ||
                peak_boundary_error || peak_restart_error) begin
                errors = errors + 1;
                $display("FAIL unexpected full-size search error flags");
            end
        end
    end

    initial begin
        $readmemh("fpga/tb/vectors/lora_sf7_l8_matched_filter_stimulus_q10.mem",
                  stimulus);
        $readmemh("fpga/tb/vectors/lora_sf7_l8_matched_filter_power.mem",
                  expected_power);

        repeat (6) @(posedge clk);
        resetn <= 1'b1;
        repeat (2) @(posedge clk);

        for (sample_index = 0; sample_index < STIMULUS_SAMPLES;
             sample_index = sample_index + 1) begin
            @(negedge clk);
            iq_in_re <= stimulus[sample_index][31:16];
            iq_in_im <= stimulus[sample_index][15:0];
            sample_valid <= 1'b1;
        end
        @(negedge clk);
        sample_valid <= 1'b0;
        iq_in_re <= 16'sd0;
        iq_in_im <= 16'sd0;

        @(negedge clk);
        search_start <= 1'b1;
        @(negedge clk);
        search_start <= 1'b0;

        while (triplet_seen == 0 && timeout_cycles < 50000) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        repeat (4) @(posedge clk);

        if (correlation_seen != SEARCH_LAGS) begin
            errors = errors + 1;
            $display("FAIL expected %0d correlation results, got=%0d",
                     SEARCH_LAGS, correlation_seen);
        end
        if (triplet_seen != 1) begin
            errors = errors + 1;
            $display("FAIL expected one triplet, got=%0d", triplet_seen);
        end
        if (search_first_count !== 64'd0) begin
            errors = errors + 1;
            $display("FAIL search first count got=%0d expected=0", search_first_count);
        end

        if (errors == 0)
            $display("PASS tb_lora_matched_filter_search_sf7_l8");
        else begin
            $display("FAIL tb_lora_matched_filter_search_sf7_l8 errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end

endmodule

