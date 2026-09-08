// The joint up/down grid estimator must actually finish.
//
// tb_lora_packet_toa_receiver_top stops driving samples 1040 short of the
// down-search window, so the controller parks in WAIT_DOWN_DATA forever and
// that regression still passes: it checks the ToA metadata and the error bits,
// but never that a fine correction was produced. A board build shipped with
// the joint path silently doing nothing because of exactly that gap.
//
// This regression drives past the down-search window and requires the
// controller to reach a fine resync request, with no history read miss on the
// way. It fails if the estimator merely parks.

`timescale 1ns/1ps

module tb_lora_joint_grid_completion;
    localparam integer SF = 7;
    localparam integer SAMPLES_PER_CHIP = 8;
    localparam integer SYMBOL_COUNT = (1 << SF);
    localparam integer SAMPLES_PER_SYMBOL = SYMBOL_COUNT * SAMPLES_PER_CHIP;
    localparam real PI = 3.14159265358979323846;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg resetn = 1'b0;
    reg signed [15:0] iq_in_re = 16'sd0;
    reg signed [15:0] iq_in_im = 16'sd0;
    reg valid_in = 1'b0;
    reg reset_in = 1'b0;
    reg resync_valid = 1'b0;
    reg [31:0] resync_skip = 32'd0;
    reg [7:0] sync_word = 8'h12;

    reg [5:0] awaddr = 6'd0;
    reg awvalid = 1'b0;
    wire awready;
    reg [31:0] wdata = 32'd0;
    reg [3:0] wstrb = 4'd0;
    reg wvalid = 1'b0;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    reg bready = 1'b0;
    reg [5:0] araddr = 6'd0;
    reg arvalid = 1'b0;
    wire arready;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;
    reg rready = 1'b0;

    wire receiver_enable;
    wire [31:0] symbol_index;
    wire symbol_valid;
    wire detected;
    wire preamble_detected;
    wire sync_valid;
    wire [63:0] packet_start_count;
    wire packet_start_valid;
    wire toa_search_busy;
    wire [63:0] toa_search_first_count;
    wire [31:0] correlation_magnitude;
    wire correlation_magnitude_valid;
    wire [63:0] correlation_sample_count;
    wire [15:0] peak_index;
    wire [63:0] peak_sample_count;
    wire peak_triplet_valid;
    wire signed [31:0] toa_offset_q12;
    wire toa_offset_valid;
    wire signed [31:0] toa_log_peak_q12;
    wire [63:0] metadata_coarse;
    wire signed [31:0] metadata_fractional_q12;
    wire metadata_valid;
    wire [63:0] history_next_sample_count;
    wire [63:0] history_oldest_sample_count;
    wire [31:0] history_samples_retained;
    wire alignment_error;
    wire symbol_index_width_error;
    wire metadata_overflow;
    wire toa_underflow_error;
    wire toa_search_restart_error;
    wire toa_mac_window_mismatch_error;
    wire toa_mac_read_miss_error;
    wire toa_mac_response_mismatch_error;
    wire toa_mac_restart_error;
    wire toa_peak_boundary_error;
    wire toa_peak_restart_error;

    integer errors = 0;
    integer symbol_seen = 0;
    integer packet_start_seen = 0;
    // On the board one 1 MS/s sample arrives roughly every 63 clocks of the
    // 62.5 MHz receiver. Driving a sample every clock hides anything that
    // depends on how much history has accumulated when a search launches, so
    // the gap is selectable: +sample_gap=63 reproduces the board's density.
    integer sample_gap = 0;
    // On the board the packet lands at an arbitrary phase, so chips_to_boundary
    // sweeps the whole symbol and the coarse resync withholds a large advance.
    // A packet driven straight onto the grid gives chips_to_boundary = 0 and
    // never exercises that against the joint search.
    integer grid_phase = 0;
    integer joint_search_start_seen = 0;
    integer joint_search_failed_seen = 0;
    integer joint_timing_valid_seen = 0;
    integer joint_fine_resync_seen = 0;
    integer joint_range_error_seen = 0;
    integer correlation_seen = 0;
    integer triplet_seen = 0;
    integer toa_seen = 0;
    integer metadata_seen = 0;
    integer timeout_cycles = 0;
    reg [31:0] expected_symbol [0:10];
    reg [31:0] read_value;
    reg [63:0] captured_metadata_coarse = 64'd0;
    reg signed [31:0] captured_metadata_fractional = 32'sd0;

    lora_packet_toa_receiver_top dut (
        .clk(clk), .resetn(resetn),
        .iq_in_re(iq_in_re), .iq_in_im(iq_in_im), .valid_in(valid_in),
        .reset_in(reset_in), .resync_valid(resync_valid),
        .resync_skip(resync_skip), .sync_word(sync_word),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid),
        .s_axi_awready(awready), .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid),
        .s_axi_wready(wready), .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid),
        .s_axi_arready(arready), .s_axi_rdata(rdata),
        .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .receiver_enable(receiver_enable), .symbol_index(symbol_index),
        .symbol_valid(symbol_valid), .detected(detected),
        .preamble_detected(preamble_detected), .sync_valid(sync_valid),
        .packet_start_count(packet_start_count),
        .packet_start_valid(packet_start_valid),
        .toa_search_busy(toa_search_busy),
        .toa_search_first_count(toa_search_first_count),
        .correlation_magnitude(correlation_magnitude),
        .correlation_magnitude_valid(correlation_magnitude_valid),
        .correlation_sample_count(correlation_sample_count),
        .peak_index(peak_index), .peak_sample_count(peak_sample_count),
        .peak_triplet_valid(peak_triplet_valid),
        .toa_offset_q12(toa_offset_q12), .toa_offset_valid(toa_offset_valid),
        .toa_log_peak_q12(toa_log_peak_q12),
        .metadata_coarse(metadata_coarse),
        .metadata_fractional_q12(metadata_fractional_q12),
        .metadata_valid(metadata_valid),
        .history_next_sample_count(history_next_sample_count),
        .history_oldest_sample_count(history_oldest_sample_count),
        .history_samples_retained(history_samples_retained),
        .alignment_error(alignment_error),
        .symbol_index_width_error(symbol_index_width_error),
        .metadata_overflow(metadata_overflow),
        .toa_underflow_error(toa_underflow_error),
        .toa_search_restart_error(toa_search_restart_error),
        .toa_mac_window_mismatch_error(toa_mac_window_mismatch_error),
        .toa_mac_read_miss_error(toa_mac_read_miss_error),
        .toa_mac_response_mismatch_error(toa_mac_response_mismatch_error),
        .toa_mac_restart_error(toa_mac_restart_error),
        .toa_peak_boundary_error(toa_peak_boundary_error),
        .toa_peak_restart_error(toa_peak_restart_error)
    );

    function automatic integer quantize_q10(input real value);
        real scaled;
        begin
            scaled = value * 1024.0;
            if (scaled >= 0.0)
                quantize_q10 = $rtoi(scaled + 0.5);
            else
                quantize_q10 = $rtoi(scaled - 0.5);
        end
    endfunction

    task automatic drive_css_symbol(input integer symbol_value);
        integer n;
        integer source_n;
        integer q_re;
        integer q_im;
        real phase_cycles;
        real angle;
        begin
            for (n = 0; n < SAMPLES_PER_SYMBOL; n = n + 1) begin
                source_n = (n + symbol_value * SAMPLES_PER_CHIP) %
                           SAMPLES_PER_SYMBOL;
                phase_cycles = (0.5 * source_n * source_n) /
                               (SYMBOL_COUNT * SAMPLES_PER_CHIP *
                                SAMPLES_PER_CHIP) -
                               (0.5 * source_n) / SAMPLES_PER_CHIP;
                angle = 2.0 * PI * phase_cycles;
                q_re = quantize_q10($cos(angle));
                q_im = quantize_q10($sin(angle));
                @(negedge clk);
                iq_in_re <= q_re;
                iq_in_im <= q_im;
                valid_in <= 1'b1;
                if (sample_gap > 0) begin
                    @(negedge clk);
                    valid_in <= 1'b0;
                    repeat (sample_gap - 1) @(negedge clk);
                end
            end
        end
    endtask

    task automatic drive_partial_symbol(input integer count);
        integer n;
        integer q_re;
        integer q_im;
        real phase_cycles;
        real angle;
        begin
            for (n = 0; n < count; n = n + 1) begin
                phase_cycles = (0.5 * n * n) /
                               (SYMBOL_COUNT * SAMPLES_PER_CHIP *
                                SAMPLES_PER_CHIP) -
                               (0.5 * n) / SAMPLES_PER_CHIP;
                angle = 2.0 * PI * phase_cycles;
                q_re = quantize_q10($cos(angle));
                q_im = quantize_q10($sin(angle));
                @(negedge clk);
                iq_in_re <= q_re;
                iq_in_im <= q_im;
                valid_in <= 1'b1;
                if (sample_gap > 0) begin
                    @(negedge clk);
                    valid_in <= 1'b0;
                    repeat (sample_gap - 1) @(negedge clk);
                end
            end
        end
    endtask

    task automatic axi_write(input [5:0] address, input [31:0] value);
        begin
            @(negedge clk);
            awaddr = address; awvalid = 1'b1;
            wdata = value; wstrb = 4'hf; wvalid = 1'b1;
            while (!(awready && wready)) @(negedge clk);
            @(negedge clk);
            awvalid = 1'b0; wvalid = 1'b0; wstrb = 4'd0;
            while (!bvalid) @(negedge clk);
            if (bresp !== 2'b00) errors = errors + 1;
            bready = 1'b1;
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task automatic axi_read(input [5:0] address, output [31:0] value);
        begin
            @(negedge clk);
            araddr = address; arvalid = 1'b1;
            while (!arready) @(negedge clk);
            @(negedge clk);
            arvalid = 1'b0;
            while (!rvalid) @(negedge clk);
            value = rdata;
            if (rresp !== 2'b00) errors = errors + 1;
            rready = 1'b1;
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (resetn) begin
            // The symbol and correlation sequences belong to
            // tb_lora_packet_toa_receiver_top, which stops at eleven symbols.
            // This test deliberately drives past that, so it counts these
            // events without asserting the shorter expected sequence.
            if (symbol_valid)
                symbol_seen = symbol_seen + 1;
            if (dut.g_joint_grid_timing.u_joint_grid_timing.search_start)
                joint_search_start_seen = joint_search_start_seen + 1;
            if (dut.g_joint_grid_timing.u_joint_grid_timing.search_failed)
                joint_search_failed_seen = joint_search_failed_seen + 1;
            if (dut.g_joint_grid_timing.u_joint_grid_timing.timing_valid)
                joint_timing_valid_seen = joint_timing_valid_seen + 1;
            if (dut.g_joint_grid_timing.u_joint_grid_timing.fine_resync_valid)
                joint_fine_resync_seen = joint_fine_resync_seen + 1;
            if (dut.g_joint_grid_timing.u_joint_grid_timing.timing_range_error)
                joint_range_error_seen = joint_range_error_seen + 1;
            if (packet_start_valid) begin
                packet_start_seen = packet_start_seen + 1;
                if (packet_start_count !== 64'd1024 + grid_phase) begin
                    errors = errors + 1;
                    $display("FAIL packet start got=%0d expected=%0d",
                             packet_start_count, 64'd1024 + grid_phase);
                end
            end
            if (correlation_magnitude_valid)
                correlation_seen = correlation_seen + 1;
            if (peak_triplet_valid)
                triplet_seen = triplet_seen + 1;
            if (toa_offset_valid)
                toa_seen = toa_seen + 1;
            if (metadata_valid) begin
                metadata_seen = metadata_seen + 1;
                captured_metadata_coarse <= metadata_coarse;
                captured_metadata_fractional <= metadata_fractional_q12;
                if (metadata_coarse !== 64'd1024) begin
                    errors = errors + 1;
                    $display("FAIL integrated metadata coarse=%0d", metadata_coarse);
                end
                if (metadata_fractional_q12 < -32'sd2048 ||
                    metadata_fractional_q12 > 32'sd2048) begin
                    errors = errors + 1;
                    $display("FAIL fractional ToA outside +/-0.5 sample: %0d",
                             metadata_fractional_q12);
                end
            end

            if (alignment_error || symbol_index_width_error || metadata_overflow ||
                toa_underflow_error || toa_search_restart_error ||
                toa_mac_window_mismatch_error || toa_mac_read_miss_error ||
                toa_mac_response_mismatch_error || toa_mac_restart_error ||
                toa_peak_boundary_error || toa_peak_restart_error) begin
                errors = errors + 1;
                $display("FAIL unexpected integrated receiver error flag");
            end
        end
    end

    initial begin
        expected_symbol[0]=37;
        expected_symbol[1]=0; expected_symbol[2]=0; expected_symbol[3]=0;
        expected_symbol[4]=0; expected_symbol[5]=0; expected_symbol[6]=0;
        expected_symbol[7]=0; expected_symbol[8]=0;
        expected_symbol[9]=8; expected_symbol[10]=16;

        if (!$value$plusargs("sample_gap=%d", sample_gap))
            sample_gap = 0;
        if (!$value$plusargs("grid_phase=%d", grid_phase))
            grid_phase = 0;
        $display("INFO sample_gap=%0d grid_phase=%0d", sample_gap, grid_phase);
        repeat (6) @(posedge clk);
        resetn <= 1'b1;
        repeat (3) @(posedge clk);
        axi_write(6'h00, 32'h0000_0001);

        // The non-preamble prefix keeps the confirmed packet timestamp away
        // from count zero, leaving a complete +/-16-sample ToA search window.
        if (grid_phase > 0) drive_partial_symbol(grid_phase);
        drive_css_symbol(37);
        drive_css_symbol(0); drive_css_symbol(0); drive_css_symbol(0);
        drive_css_symbol(0); drive_css_symbol(0); drive_css_symbol(0);
        drive_css_symbol(0); drive_css_symbol(0);
        drive_css_symbol(8); drive_css_symbol(16);
        // Everything above is the detection stimulus shared with
        // tb_lora_packet_toa_receiver_top. Past this point the samples exist
        // only so the down search window arrives; their content does not have
        // to be a true SFD for the completion check.
        drive_css_symbol(0); drive_css_symbol(0); drive_css_symbol(0);
        drive_css_symbol(0); drive_css_symbol(0); drive_css_symbol(0);
        @(negedge clk);
        valid_in <= 1'b0;
        iq_in_re <= 16'sd0;
        iq_in_im <= 16'sd0;

        while (joint_timing_valid_seen == 0 && timeout_cycles < 4000000) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        repeat (5) @(posedge clk);

        if (packet_start_seen != 1) begin
            errors = errors + 1;
            $display("FAIL packet starts=%0d", packet_start_seen);
        end
        if (joint_timing_valid_seen != 1) begin
            errors = errors + 1;
            $display("FAIL joint estimator never produced a timing estimate; state=%0d history_next=%0d down_ready=%0d",
                     dut.g_joint_grid_timing.u_joint_grid_timing.state,
                     history_next_sample_count,
                     dut.g_joint_grid_timing.u_joint_grid_timing.down_ready_count);
        end
        if (joint_fine_resync_seen != 1) begin
            errors = errors + 1;
            $display("FAIL no fine resync request; range_error_seen=%0d search_failed_seen=%0d",
                     joint_range_error_seen, joint_search_failed_seen);
        end
        if (joint_search_failed_seen != 0) begin
            errors = errors + 1;
            $display("FAIL joint search aborted %0d time(s)", joint_search_failed_seen);
        end
        if (toa_mac_read_miss_error) begin
            errors = errors + 1;
            $display("FAIL history read miss during the joint search");
        end

        if (errors == 0)
            $display("PASS tb_lora_joint_grid_completion grid_phase=%0d chips_to_boundary=%0d searches=%0d fine_skip=%0d",
                     grid_phase, dut.chips_to_boundary, joint_search_start_seen,
                     dut.g_joint_grid_timing.u_joint_grid_timing.fine_skip);
        else begin
            $display("FAIL tb_lora_joint_grid_completion errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end

endmodule
