`timescale 1ns/1ps

module tb_lora_joint_chirp_grid_controller;
    localparam integer SYMBOL_SAMPLES = 1024;
    localparam integer SEARCH_RADIUS = 16;
    localparam integer GUARD = 16;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg resetn = 1'b0;
    reg stream_reset = 1'b0;
    reg packet_start_valid = 1'b0;
    reg [63:0] packet_start_count = 64'd0;
    reg [15:0] chips_to_boundary = 16'd0;
    reg [63:0] history_next_sample_count = 64'd0;
    reg search_busy = 1'b0;
    reg search_failed = 1'b0;
    reg search_triplet_valid = 1'b0;
    reg [63:0] search_peak_sample_count = 64'd0;

    wire search_start;
    wire [63:0] search_coarse_start;
    wire reference_down;
    wire busy;
    wire signed [31:0] timing_correction_samples;
    wire [31:0] fine_skip;
    wire fine_resync_valid;
    wire timing_valid;
    wire restart_error;
    wire timing_range_error;

    integer errors = 0;

    initial begin
        #1000000;
        $display("FAIL timeout state=%0d busy=%0d search_start=%0d down=%0d history=%0d down_start=%0d ready=%0d",
                 dut.state, busy, search_start, reference_down,
                 history_next_sample_count, dut.down_coarse_start,
                 dut.down_ready_count);
        $fatal(1);
    end

    lora_joint_chirp_grid_controller #(
        .SAMPLES_PER_CHIP(8),
        .SYMBOL_SAMPLES(SYMBOL_SAMPLES),
        .SEARCH_RADIUS(SEARCH_RADIUS),
        .FINE_GUARD_SAMPLES(GUARD),
        .PREAMBLE_TO_SFD_SYMBOLS(10)
    ) dut (
        .clk(clk), .resetn(resetn), .stream_reset(stream_reset),
        .packet_start_valid(packet_start_valid),
        .packet_start_count(packet_start_count),
        .chips_to_boundary(chips_to_boundary),
        .history_next_sample_count(history_next_sample_count),
        .search_busy(search_busy),
        .search_failed(search_failed),
        .search_triplet_valid(search_triplet_valid),
        .search_peak_sample_count(search_peak_sample_count),
        .search_start(search_start),
        .search_coarse_start(search_coarse_start),
        .reference_down(reference_down), .busy(busy),
        .timing_correction_samples(timing_correction_samples),
        .fine_skip(fine_skip), .fine_resync_valid(fine_resync_valid),
        .timing_valid(timing_valid), .restart_error(restart_error),
        .timing_range_error(timing_range_error)
    );

    task automatic pulse_packet(input [63:0] start_count, input [15:0] chips);
        begin
            @(negedge clk);
            packet_start_count <= start_count;
            chips_to_boundary <= chips;
            packet_start_valid <= 1'b1;
            @(negedge clk);
            packet_start_valid <= 1'b0;
        end
    endtask

    task automatic wait_search(
        input expected_down,
        input [63:0] expected_start
    );
        begin
            while (!search_start) @(negedge clk);
            if (reference_down !== expected_down ||
                search_coarse_start !== expected_start) begin
                errors = errors + 1;
                $display("FAIL search down=%0d start=%0d expected down=%0d start=%0d",
                         reference_down, search_coarse_start,
                         expected_down, expected_start);
            end
            search_busy <= 1'b1;
            @(negedge clk);
        end
    endtask

    task automatic return_peak(input [63:0] count);
        begin
            search_busy <= 1'b0;
            search_peak_sample_count <= count;
            search_triplet_valid <= 1'b1;
            @(negedge clk);
            search_triplet_valid <= 1'b0;
        end
    endtask

    task automatic expect_result(
        input signed [31:0] expected_correction,
        input [31:0] expected_skip
    );
        begin
            while (!timing_valid) @(negedge clk);
            if (timing_correction_samples !== expected_correction ||
                fine_skip !== expected_skip || !fine_resync_valid ||
                timing_range_error) begin
                errors = errors + 1;
                $display("FAIL result correction=%0d skip=%0d fine=%0d range=%0d",
                         timing_correction_samples, fine_skip,
                         fine_resync_valid, timing_range_error);
            end
            @(negedge clk);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        resetn <= 1'b1;
        repeat (2) @(posedge clk);

        // Capture 30: coarse up=10440, down=20680; offsets +8 and +14
        // have half-sum +11, so the guarded late skip is 16+11=27.
        history_next_sample_count <= 64'd200000;
        pulse_packet(64'd10000, 16'd55);
        wait_search(1'b0, 64'd10440);
        return_peak(64'd10448);
        wait_search(1'b1, 64'd20680);
        return_peak(64'd20694);
        expect_result(32'sd11, 32'd27);

        // Synthetic negative half-sum: chirp origin 30832 is 192 samples
        // before FFT window 31024 (previous window 30000); its forward phase
        // is (1024-192)/8 = 104 chips. Offsets (-5 + 2)/2 round to -2.
        pulse_packet(64'd31024, 16'd104);
        wait_search(1'b0, 64'd30832);
        return_peak(64'd30827);
        wait_search(1'b1, 64'd41072);
        return_peak(64'd41074);
        expect_result(-32'sd2, 32'd14);

        // Synthetic positive half-sum: chirp origin 50872 is 152 before 51024,
        // so its forward phase is (1024-152)/8 = 109 chips.
        // (-2 + 5)/2 = +1.5, rounded away from zero to +2.
        pulse_packet(64'd51024, 16'd109);
        wait_search(1'b0, 64'd50872);
        return_peak(64'd50870);
        wait_search(1'b1, 64'd61112);
        return_peak(64'd61117);
        expect_result(32'sd2, 32'd18);

        // A packet at 60512 lies halfway between grid origins 60000/61024.
        // The later decision window represents it; phase 64 chips must point
        // backwards to that packet, with the SFD at 60512 + 10*1024.
        pulse_packet(64'd61024, 16'd64);
        wait_search(1'b0, 64'd60512);
        return_peak(64'd60512);
        wait_search(1'b1, 64'd70752);
        return_peak(64'd70752);
        expect_result(32'sd0, 32'd16);

        // Neither search may start until its complete window is stored. The
        // up window here ends at 70008+1024+16 = 71048; the down window ends
        // at 81288, so this level releases the up search and still holds the
        // down one back.
        history_next_sample_count <= 64'd0;
        pulse_packet(64'd70000, 16'd1);
        repeat (5) begin
            @(negedge clk);
            if (search_start) begin
                errors = errors + 1;
                $display("FAIL up search started before IQ was available");
            end
        end
        history_next_sample_count <= 64'd71048;
        wait_search(1'b0, 64'd70008);
        return_peak(64'd70008);
        repeat (5) begin
            @(negedge clk);
            if (search_start) begin
                errors = errors + 1;
                $display("FAIL down search started before IQ was available");
            end
        end
        history_next_sample_count <= 64'd81288;
        wait_search(1'b1, 64'd80248);
        return_peak(64'd80248);
        expect_result(32'sd0, 32'd16);

        // A new packet while the pair is active is diagnosed, not restarted.
        history_next_sample_count <= 64'd200000;
        pulse_packet(64'd90000, 16'd0);
        wait_search(1'b0, 64'd90000);
        packet_start_valid <= 1'b1;
        @(negedge clk);
        packet_start_valid <= 1'b0;
        if (!restart_error) begin
            errors = errors + 1;
            $display("FAIL missing restart error");
        end
        return_peak(64'd90000);
        wait_search(1'b1, 64'd100240);
        return_peak(64'd100240);
        expect_result(32'sd0, 32'd16);

        // A failed bounded search releases the controller for the next packet.
        pulse_packet(64'd120000, 16'd0);
        wait_search(1'b0, 64'd120000);
        search_busy <= 1'b0;
        search_failed <= 1'b1;
        @(negedge clk);
        search_failed <= 1'b0;
        repeat (2) @(negedge clk);
        if (busy) begin
            errors = errors + 1;
            $display("FAIL failed search left controller busy");
        end

        if (errors) begin
            $display("FAIL tb_lora_joint_chirp_grid_controller (%0d errors)", errors);
            $fatal(1);
        end
        $display("PASS tb_lora_joint_chirp_grid_controller");
        $finish;
    end
endmodule
