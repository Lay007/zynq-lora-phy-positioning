`timescale 1ns/1ps

module tb_lora_matched_filter_search;
    localparam integer DEPTH = 32;
    localparam integer REF_SAMPLES = 1;
    localparam integer SEARCH_RADIUS = 2;
    localparam integer ACC_WIDTH = 40;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg resetn = 1'b0;
    reg stream_reset = 1'b0;

    reg signed [15:0] iq_in_re = 16'sd0;
    reg signed [15:0] iq_in_im = 16'sd0;
    reg sample_valid = 1'b0;

    reg search_start = 1'b0;
    reg [63:0] coarse_start_count = 64'd0;

    wire iq_read_req;
    wire [63:0] iq_read_sample_count;
    wire signed [15:0] iq_read_re;
    wire signed [15:0] iq_read_im;
    wire [63:0] iq_read_sample_count_out;
    wire iq_read_valid;
    wire iq_read_miss;

    wire [15:0] reference_index;
    wire signed [15:0] reference_re = 16'sd1;
    wire signed [15:0] reference_im = 16'sd0;

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

    wire [63:0] next_sample_count;
    wire [63:0] oldest_sample_count;
    wire [31:0] samples_retained;

    integer errors = 0;
    integer timeout_cycles = 0;
    integer corr_seen = 0;
    reg nominal_monitor = 1'b0;
    reg restart_seen = 1'b0;
    reg underflow_seen = 1'b0;
    reg boundary_seen = 1'b0;
    reg read_miss_seen = 1'b0;
    reg triplet_seen = 1'b0;

    reg [31:0] expected_power [0:4];

    lora_iq_history_buffer #(
        .DEPTH(DEPTH)
    ) u_history (
        .clk(clk),
        .resetn(resetn),
        .stream_reset(stream_reset),
        .iq_in_re(iq_in_re),
        .iq_in_im(iq_in_im),
        .sample_valid(sample_valid),
        .read_req(iq_read_req),
        .read_sample_count(iq_read_sample_count),
        .read_iq_re(iq_read_re),
        .read_iq_im(iq_read_im),
        .read_sample_count_out(iq_read_sample_count_out),
        .read_valid(iq_read_valid),
        .read_miss(iq_read_miss),
        .next_sample_count(next_sample_count),
        .oldest_sample_count(oldest_sample_count),
        .samples_retained(samples_retained)
    );

    lora_matched_filter_search #(
        .REF_SAMPLES(REF_SAMPLES),
        .SEARCH_RADIUS(SEARCH_RADIUS),
        .ACC_WIDTH(ACC_WIDTH),
        .POWER_SHIFT(0)
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .stream_reset(stream_reset),
        .start(search_start),
        .coarse_start_count(coarse_start_count),
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
        .busy(search_busy),
        .search_first_count(search_first_count),
        .correlation_magnitude(correlation_magnitude),
        .correlation_magnitude_valid(correlation_magnitude_valid),
        .correlation_sample_count(correlation_sample_count),
        .magnitude_before(magnitude_before),
        .magnitude_peak(magnitude_peak),
        .magnitude_after(magnitude_after),
        .peak_index(peak_index),
        .peak_sample_count(peak_sample_count),
        .triplet_valid(triplet_valid),
        .underflow_error(underflow_error),
        .search_restart_error(search_restart_error),
        .mac_window_mismatch_error(mac_window_mismatch_error),
        .mac_read_miss_error(mac_read_miss_error),
        .mac_response_mismatch_error(mac_response_mismatch_error),
        .mac_restart_error(mac_restart_error),
        .peak_boundary_error(peak_boundary_error),
        .peak_restart_error(peak_restart_error)
    );

    task automatic expect1(input logic got, input logic expected, input string label_text);
        begin
            if (got === expected)
                $display("PASS %-64s value=%0d", label_text, got);
            else begin
                errors = errors + 1;
                $display("FAIL %-64s got=%0b expected=%0b", label_text, got, expected);
            end
        end
    endtask

    task automatic expect32(input [31:0] got, input [31:0] expected, input string label_text);
        begin
            if (got === expected)
                $display("PASS %-64s value=0x%08x", label_text, got);
            else begin
                errors = errors + 1;
                $display("FAIL %-64s got=0x%08x expected=0x%08x", label_text, got, expected);
            end
        end
    endtask

    task automatic expect64(input [63:0] got, input [63:0] expected, input string label_text);
        begin
            if (got === expected)
                $display("PASS %-64s value=0x%016x", label_text, got);
            else begin
                errors = errors + 1;
                $display("FAIL %-64s got=0x%016x expected=0x%016x", label_text, got, expected);
            end
        end
    endtask

    task automatic drive_sample(input integer re_value, input integer im_value);
        begin
            @(negedge clk);
            iq_in_re <= re_value;
            iq_in_im <= im_value;
            sample_valid <= 1'b1;
        end
    endtask

    task automatic stop_samples;
        begin
            @(negedge clk);
            sample_valid <= 1'b0;
            iq_in_re <= 16'sd0;
            iq_in_im <= 16'sd0;
        end
    endtask

    task automatic pulse_search(input [63:0] coarse_count);
        begin
            @(negedge clk);
            coarse_start_count <= coarse_count;
            search_start <= 1'b1;
            @(negedge clk);
            search_start <= 1'b0;
        end
    endtask

    task automatic pulse_stream_reset;
        begin
            @(negedge clk);
            stream_reset <= 1'b1;
            @(negedge clk);
            stream_reset <= 1'b0;
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (resetn) begin
            if (search_restart_error)
                restart_seen = 1'b1;
            if (underflow_error)
                underflow_seen = 1'b1;
            if (peak_boundary_error)
                boundary_seen = 1'b1;
            if (mac_read_miss_error)
                read_miss_seen = 1'b1;
            if (triplet_valid)
                triplet_seen = 1'b1;

            if (reference_index !== 16'd0 && iq_read_req) begin
                errors = errors + 1;
                $display("FAIL REF_SAMPLES=1 requested unexpected reference index=%0d", reference_index);
            end

            if (mac_response_mismatch_error || mac_restart_error ||
                mac_window_mismatch_error || peak_restart_error) begin
                errors = errors + 1;
                $display("FAIL unexpected search integration error response=%0b mac_restart=%0b window=%0b peak_restart=%0b",
                         mac_response_mismatch_error, mac_restart_error,
                         mac_window_mismatch_error, peak_restart_error);
            end

            if (nominal_monitor && correlation_magnitude_valid) begin
                if (corr_seen < 5) begin
                    if (correlation_sample_count === (64'd4 + corr_seen))
                        $display("PASS correlation lag[%0d] absolute sample count                      value=0x%016h",
                                 corr_seen, correlation_sample_count);
                    else begin
                        errors = errors + 1;
                        $display("FAIL correlation lag[%0d] count got=0x%016h expected=0x%016h",
                                 corr_seen, correlation_sample_count, 64'd4 + corr_seen);
                    end

                    if (correlation_magnitude === expected_power[corr_seen])
                        $display("PASS correlation lag[%0d] power                                      value=0x%08h",
                                 corr_seen, correlation_magnitude);
                    else begin
                        errors = errors + 1;
                        $display("FAIL correlation lag[%0d] power got=0x%08h expected=0x%08h",
                                 corr_seen, correlation_magnitude, expected_power[corr_seen]);
                    end
                end else begin
                    errors = errors + 1;
                    $display("FAIL nominal search emitted more than five lag results");
                end
                corr_seen = corr_seen + 1;
            end
        end
    end

    initial begin
        expected_power[0] = 32'd1;
        expected_power[1] = 32'd4;
        expected_power[2] = 32'd25;
        expected_power[3] = 32'd9;
        expected_power[4] = 32'd1;

        repeat (6) @(posedge clk);
        resetn <= 1'b1;
        repeat (3) @(posedge clk);

        expect1(search_busy, 1'b0, "search busy reset");
        expect1(triplet_valid, 1'b0, "search triplet valid reset");
        expect1(underflow_error, 1'b0, "search underflow error reset");

        // Absolute samples 4..8 contain amplitudes 1,2,5,3,1. With a
        // one-sample unit reference their matched-filter powers are exactly
        // 1,4,25,9,1, so the centered lag (absolute sample 6) must win.
        drive_sample(0, 0);  // 0
        drive_sample(0, 0);  // 1
        drive_sample(0, 0);  // 2
        drive_sample(0, 0);  // 3
        drive_sample(1, 0);  // 4
        drive_sample(2, 0);  // 5
        drive_sample(5, 0);  // 6
        drive_sample(3, 0);  // 7
        drive_sample(1, 0);  // 8
        drive_sample(0, 0);  // 9
        drive_sample(0, 0);  // 10
        drive_sample(0, 0);  // 11
        stop_samples();
        repeat (2) @(posedge clk);

        expect64(next_sample_count, 64'd12, "history contains twelve accepted samples");
        expect64(oldest_sample_count, 64'd0, "history has not wrapped before search tests");

        nominal_monitor = 1'b1;
        corr_seen = 0;
        triplet_seen = 1'b0;
        restart_seen = 1'b0;
        pulse_search(64'd6);
        expect1(search_busy, 1'b1, "centered search becomes busy");
        expect64(search_first_count, 64'd4, "centered search starts at coarse minus radius");

        // A second request while the five-lag search is active is rejected but
        // must not disturb the original candidate window.
        pulse_search(64'd7);

        timeout_cycles = 0;
        while (!triplet_seen && timeout_cycles < 500) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        if (!triplet_seen) begin
            errors = errors + 1;
            $display("FAIL centered search timed out waiting for peak triplet");
        end

        nominal_monitor = 1'b0;
        if (corr_seen == 5)
            $display("PASS centered search emits exactly five integer-lag correlations");
        else begin
            errors = errors + 1;
            $display("FAIL centered search correlation count got=%0d expected=5", corr_seen);
        end
        expect1(restart_seen, 1'b1, "restart while search busy is reported");
        expect32(magnitude_before, 32'd4, "peak-search left neighbour comes from lag -1");
        expect32(magnitude_peak, 32'd25, "peak-search center power");
        expect32(magnitude_after, 32'd9, "peak-search right neighbour comes from lag +1");
        expect32({16'd0, peak_index}, 32'd2, "peak index is centered inside five-lag window");
        expect64(peak_sample_count, 64'd6, "peak sample count returns integer-refined ToA");

        repeat (2) @(posedge clk);
        #1;
        expect1(triplet_valid, 1'b0, "peak triplet valid is one-cycle pulse");
        expect1(search_busy, 1'b0, "search returns idle after triplet");

        // Candidate counts 7..11 have powers 9,1,0,0,0. The strongest point
        // lies on the first search boundary and must therefore be rejected.
        boundary_seen = 1'b0;
        triplet_seen = 1'b0;
        pulse_search(64'd9);
        timeout_cycles = 0;
        while (!boundary_seen && timeout_cycles < 500) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        expect1(boundary_seen, 1'b1, "boundary maximum is propagated by search sequencer");
        expect1(triplet_seen, 1'b0, "boundary maximum emits no refined triplet");
        repeat (2) @(posedge clk);
        #1;
        expect1(search_busy, 1'b0, "boundary rejection returns search idle");

        // A centered window cannot subtract the configured radius below zero.
        underflow_seen = 1'b0;
        pulse_search(64'd1);
        repeat (1) @(posedge clk);
        expect1(underflow_seen, 1'b1, "coarse count below radius raises underflow error");
        expect1(search_busy, 1'b0, "underflow request never starts MAC search");

        // Abort path: only samples 0..4 exist, while coarse=4 requests lags
        // 2..6. The search must stop on the first missing absolute IQ sample and
        // clear the partially filled peak collector.
        pulse_stream_reset();
        drive_sample(1, 0);  // 0
        drive_sample(1, 0);  // 1
        drive_sample(1, 0);  // 2
        drive_sample(1, 0);  // 3
        drive_sample(1, 0);  // 4
        stop_samples();
        repeat (2) @(posedge clk);

        read_miss_seen = 1'b0;
        triplet_seen = 1'b0;
        pulse_search(64'd4);
        timeout_cycles = 0;
        while (!read_miss_seen && timeout_cycles < 500) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        expect1(read_miss_seen, 1'b1, "missing retained IQ aborts multi-lag search");
        expect1(triplet_seen, 1'b0, "aborted partial search emits no triplet");
        repeat (2) @(posedge clk);
        #1;
        expect1(search_busy, 1'b0, "read-miss abort returns search idle");

        // Complete the same history after the abort. A fresh search must work,
        // proving that the partial peak collector was reset rather than left
        // busy with stale magnitudes.
        drive_sample(2, 0);  // 5
        drive_sample(5, 0);  // 6
        drive_sample(3, 0);  // 7
        drive_sample(1, 0);  // 8
        stop_samples();
        repeat (2) @(posedge clk);

        triplet_seen = 1'b0;
        pulse_search(64'd6);
        timeout_cycles = 0;
        while (!triplet_seen && timeout_cycles < 500) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        expect1(triplet_seen, 1'b1, "fresh search succeeds after read-miss abort");
        expect64(peak_sample_count, 64'd6, "fresh search after abort keeps absolute ToA");
        expect32(magnitude_peak, 32'd25, "fresh search after abort recovers peak power");

        // Stream reset is the authoritative abort for both search and history.
        pulse_search(64'd6);
        repeat (2) @(posedge clk);
        pulse_stream_reset();
        repeat (2) @(posedge clk);
        #1;
        expect1(search_busy, 1'b0, "stream reset aborts in-flight multi-lag search");
        expect64(next_sample_count, 64'd0, "stream reset restarts shared IQ sample epoch");
        expect1(triplet_valid, 1'b0, "stream reset clears peak triplet pulse");

        if (errors == 0)
            $display("PASS tb_lora_matched_filter_search");
        else begin
            $display("FAIL tb_lora_matched_filter_search errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule
