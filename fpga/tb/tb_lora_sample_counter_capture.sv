`timescale 1ns/1ps

module tb_lora_sample_counter_capture;
    localparam integer WIDTH = 4;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg sample_valid = 1'b0;
    reg capture = 1'b0;

    wire [WIDTH-1:0] sample_count;
    wire [WIDTH-1:0] captured_sample_count;
    wire capture_valid;

    integer errors = 0;

    always #5 clk = ~clk;

    lora_sample_counter_capture #(
        .COUNTER_WIDTH(WIDTH)
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .sample_valid(sample_valid),
        .capture(capture),
        .sample_count(sample_count),
        .captured_sample_count(captured_sample_count),
        .capture_valid(capture_valid)
    );

    task automatic expect4(
        input [WIDTH-1:0] got,
        input [WIDTH-1:0] expected,
        input [8*48-1:0] label
    );
        begin
            if (got !== expected) begin
                $display("FAIL %-48s got=0x%0x expected=0x%0x", label, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS %-48s value=0x%0x", label, got);
            end
        end
    endtask

    task automatic expect1(
        input got,
        input expected,
        input [8*48-1:0] label
    );
        begin
            if (got !== expected) begin
                $display("FAIL %-48s got=%0b expected=%0b", label, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS %-48s value=%0b", label, got);
            end
        end
    endtask

    task automatic pulse_sample;
        begin
            @(negedge clk);
            sample_valid = 1'b1;
            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    task automatic pulse_capture;
        begin
            @(negedge clk);
            capture = 1'b1;
            @(negedge clk);
            capture = 1'b0;
        end
    endtask

    task automatic pulse_sample_and_capture;
        begin
            @(negedge clk);
            sample_valid = 1'b1;
            capture = 1'b1;
            @(negedge clk);
            sample_valid = 1'b0;
            capture = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        resetn = 1'b1;
        repeat (1) @(negedge clk);

        expect4(sample_count, 4'h0, "counter reset value");
        expect4(captured_sample_count, 4'h0, "snapshot reset value");
        expect1(capture_valid, 1'b0, "capture valid reset value");

        repeat (3) pulse_sample();
        expect4(sample_count, 4'h3, "three accepted samples counted");

        repeat (3) @(negedge clk);
        expect4(sample_count, 4'h3, "idle cycles do not increment counter");

        pulse_capture();
        expect4(captured_sample_count, 4'h3, "capture snapshots accepted-sample count");
        expect1(capture_valid, 1'b1, "capture valid asserted after capture edge");
        @(negedge clk);
        expect1(capture_valid, 1'b0, "capture valid is one cycle pulse");

        pulse_sample_and_capture();
        expect4(captured_sample_count, 4'h3, "same-edge capture uses pre-increment count");
        expect4(sample_count, 4'h4, "same-edge sample increments live counter");

        // WIDTH=4 makes wraparound reachable in a short simulation.
        repeat (12) pulse_sample();
        expect4(sample_count, 4'h0, "counter wraps modulo 2^WIDTH");

        pulse_sample_and_capture();
        expect4(captured_sample_count, 4'h0, "capture at wrap boundary sees pre-increment zero");
        expect4(sample_count, 4'h1, "counter advances after wrap-boundary capture");

        @(negedge clk);
        resetn = 1'b0;
        @(negedge clk);
        expect4(sample_count, 4'h0, "synchronous reset clears live counter");
        expect4(captured_sample_count, 4'h0, "synchronous reset clears snapshot");
        expect1(capture_valid, 1'b0, "synchronous reset clears capture valid");

        if (errors == 0) begin
            $display("PASS tb_lora_sample_counter_capture");
            $finish;
        end

        $display("FAIL tb_lora_sample_counter_capture errors=%0d", errors);
        $fatal(1);
    end
endmodule
