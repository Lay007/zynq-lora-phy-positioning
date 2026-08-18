`timescale 1ns/1ps

module tb_lora_timestamp_metadata_join;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg resetn = 1'b0;
    reg [63:0] coarse_sample_count = 64'd0;
    reg coarse_valid = 1'b0;
    reg signed [31:0] fractional_toa_q12 = 32'sd0;
    reg fractional_valid = 1'b0;

    wire [63:0] timestamp_coarse;
    wire signed [31:0] timestamp_fractional_q12;
    wire timestamp_valid;
    wire metadata_overflow;

    lora_timestamp_metadata_join dut (
        .clk(clk),
        .resetn(resetn),
        .coarse_sample_count(coarse_sample_count),
        .coarse_valid(coarse_valid),
        .fractional_toa_q12(fractional_toa_q12),
        .fractional_valid(fractional_valid),
        .timestamp_coarse(timestamp_coarse),
        .timestamp_fractional_q12(timestamp_fractional_q12),
        .timestamp_valid(timestamp_valid),
        .metadata_overflow(metadata_overflow)
    );

    task automatic step(
        input reg rstn,
        input reg cv,
        input reg [63:0] coarse_value,
        input reg fv,
        input reg signed [31:0] fractional_value
    );
        begin
            @(negedge clk);
            resetn = rstn;
            coarse_valid = cv;
            coarse_sample_count = coarse_value;
            fractional_valid = fv;
            fractional_toa_q12 = fractional_value;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic expect_idle;
        begin
            if (timestamp_valid !== 1'b0)
                $fatal(1, "unexpected timestamp_valid");
        end
    endtask

    task automatic expect_record(
        input reg [63:0] expected_coarse,
        input reg signed [31:0] expected_fractional
    );
        begin
            if (timestamp_valid !== 1'b1)
                $fatal(1, "expected timestamp_valid");
            if (timestamp_coarse !== expected_coarse)
                $fatal(1, "coarse mismatch: got %0d expected %0d",
                    timestamp_coarse, expected_coarse);
            if (timestamp_fractional_q12 !== expected_fractional)
                $fatal(1, "fractional mismatch: got %0d expected %0d",
                    timestamp_fractional_q12, expected_fractional);
        end
    endtask

    initial begin
        // Reset clears all pending metadata.
        step(1'b0, 1'b0, 64'd0, 1'b0, 32'sd0);
        step(1'b0, 1'b0, 64'd0, 1'b0, 32'sd0);
        if (timestamp_valid !== 1'b0 || metadata_overflow !== 1'b0)
            $fatal(1, "outputs not clear during reset");
        step(1'b1, 1'b0, 64'd0, 1'b0, 32'sd0);
        expect_idle();

        // Coarse first, then fractional.
        step(1'b1, 1'b1, 64'd1000, 1'b0, 32'sd0);
        expect_idle();
        step(1'b1, 1'b0, 64'd0, 1'b1, -32'sd512);
        expect_idle();
        step(1'b1, 1'b0, 64'd0, 1'b0, 32'sd0);
        expect_record(64'd1000, -32'sd512);

        // Fractional first, then coarse.
        step(1'b1, 1'b0, 64'd0, 1'b0, 32'sd0);
        expect_idle();
        step(1'b1, 1'b0, 64'd0, 1'b1, 32'sd1024);
        expect_idle();
        step(1'b1, 1'b1, 64'd2000, 1'b0, 32'sd0);
        expect_idle();
        step(1'b1, 1'b0, 64'd0, 1'b0, 32'sd0);
        expect_record(64'd2000, 32'sd1024);

        // Both fragments in the same cycle.
        step(1'b1, 1'b0, 64'd0, 1'b0, 32'sd0);
        expect_idle();
        step(1'b1, 1'b1, 64'd3000, 1'b1, 32'sd0);
        expect_idle();
        step(1'b1, 1'b0, 64'd0, 1'b0, 32'sd0);
        expect_record(64'd3000, 32'sd0);

        // Duplicate unmatched coarse fragment reports overflow and preserves
        // the original coarse timestamp.
        step(1'b1, 1'b0, 64'd0, 1'b0, 32'sd0);
        expect_idle();
        step(1'b1, 1'b1, 64'd4000, 1'b0, 32'sd0);
        expect_idle();
        step(1'b1, 1'b1, 64'd9999, 1'b0, 32'sd0);
        if (metadata_overflow !== 1'b1)
            $fatal(1, "duplicate coarse fragment did not raise overflow");
        step(1'b1, 1'b0, 64'd0, 1'b1, 32'sd256);
        if (metadata_overflow !== 1'b0)
            $fatal(1, "metadata_overflow did not pulse for one cycle");
        expect_idle();
        step(1'b1, 1'b0, 64'd0, 1'b0, 32'sd0);
        expect_record(64'd4000, 32'sd256);

        // Reset discards a partial pair.
        step(1'b1, 1'b0, 64'd0, 1'b0, 32'sd0);
        step(1'b1, 1'b1, 64'd5000, 1'b0, 32'sd0);
        step(1'b0, 1'b0, 64'd0, 1'b0, 32'sd0);
        step(1'b1, 1'b0, 64'd0, 1'b1, -32'sd256);
        expect_idle();
        step(1'b1, 1'b1, 64'd6000, 1'b0, 32'sd0);
        expect_idle();
        step(1'b1, 1'b0, 64'd0, 1'b0, 32'sd0);
        expect_record(64'd6000, -32'sd256);

        // The first fragment of the next packet can arrive while the previous
        // complete pair is being emitted.
        step(1'b1, 1'b0, 64'd0, 1'b0, 32'sd0);
        step(1'b1, 1'b1, 64'd7000, 1'b1, 32'sd128);
        expect_idle();
        step(1'b1, 1'b1, 64'd8000, 1'b0, 32'sd0);
        expect_record(64'd7000, 32'sd128);
        step(1'b1, 1'b0, 64'd0, 1'b1, -32'sd128);
        expect_idle();
        step(1'b1, 1'b0, 64'd0, 1'b0, 32'sd0);
        expect_record(64'd8000, -32'sd128);

        $display("PASS: timestamp metadata joiner");
        $finish;
    end
endmodule
