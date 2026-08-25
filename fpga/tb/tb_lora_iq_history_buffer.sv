`timescale 1ns/1ps

module tb_lora_iq_history_buffer;
    localparam integer DEPTH = 8;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg resetn = 1'b0;
    reg stream_reset = 1'b0;
    reg signed [15:0] iq_in_re = 16'sd0;
    reg signed [15:0] iq_in_im = 16'sd0;
    reg sample_valid = 1'b0;

    reg read_req = 1'b0;
    reg [63:0] read_sample_count = 64'd0;
    wire signed [15:0] read_iq_re;
    wire signed [15:0] read_iq_im;
    wire [63:0] read_sample_count_out;
    wire read_valid;
    wire read_miss;
    wire [63:0] next_sample_count;
    wire [63:0] oldest_sample_count;
    wire [31:0] samples_retained;

    integer errors = 0;
    integer k;

    lora_iq_history_buffer #(.DEPTH(DEPTH)) dut (
        .clk(clk),
        .resetn(resetn),
        .stream_reset(stream_reset),
        .iq_in_re(iq_in_re),
        .iq_in_im(iq_in_im),
        .sample_valid(sample_valid),
        .read_req(read_req),
        .read_sample_count(read_sample_count),
        .read_iq_re(read_iq_re),
        .read_iq_im(read_iq_im),
        .read_sample_count_out(read_sample_count_out),
        .read_valid(read_valid),
        .read_miss(read_miss),
        .next_sample_count(next_sample_count),
        .oldest_sample_count(oldest_sample_count),
        .samples_retained(samples_retained)
    );

    task automatic expect64(input [63:0] got, input [63:0] expected, input string label_text);
        begin
            if (got === expected)
                $display("PASS %-58s value=0x%016h", label_text, got);
            else begin
                errors = errors + 1;
                $display("FAIL %-58s got=0x%016h expected=0x%016h", label_text, got, expected);
            end
        end
    endtask

    task automatic expect32(input [31:0] got, input [31:0] expected, input string label_text);
        begin
            if (got === expected)
                $display("PASS %-58s value=0x%08h", label_text, got);
            else begin
                errors = errors + 1;
                $display("FAIL %-58s got=0x%08h expected=0x%08h", label_text, got, expected);
            end
        end
    endtask

    task automatic expect16s(input signed [15:0] got, input signed [15:0] expected, input string label_text);
        begin
            if (got === expected)
                $display("PASS %-58s value=%0d", label_text, got);
            else begin
                errors = errors + 1;
                $display("FAIL %-58s got=%0d expected=%0d", label_text, got, expected);
            end
        end
    endtask

    task automatic expect_true(input bit condition, input string label_text);
        begin
            if (condition)
                $display("PASS %-58s", label_text);
            else begin
                errors = errors + 1;
                $display("FAIL %-58s", label_text);
            end
        end
    endtask

    task automatic write_sample(input signed [15:0] re_value, input signed [15:0] im_value);
        begin
            @(negedge clk);
            iq_in_re = re_value;
            iq_in_im = im_value;
            sample_valid = 1'b1;
            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    task automatic idle_cycle;
        begin
            @(negedge clk);
            sample_valid = 1'b0;
            @(negedge clk);
        end
    endtask

    task automatic read_expect(
        input [63:0] count,
        input signed [15:0] expected_re,
        input signed [15:0] expected_im,
        input string label_text
    );
        begin
            @(negedge clk);
            read_sample_count = count;
            read_req = 1'b1;
            @(negedge clk);
            read_req = 1'b0;

            expect_true(read_valid && !read_miss, {label_text, " valid"});
            expect64(read_sample_count_out, count, {label_text, " count"});
            expect16s(read_iq_re, expected_re, {label_text, " real"});
            expect16s(read_iq_im, expected_im, {label_text, " imag"});

            @(negedge clk);
            expect_true(!read_valid && !read_miss, {label_text, " response is one-cycle pulse"});
        end
    endtask

    task automatic read_expect_miss(input [63:0] count, input string label_text);
        begin
            @(negedge clk);
            read_sample_count = count;
            read_req = 1'b1;
            @(negedge clk);
            read_req = 1'b0;

            expect_true(!read_valid && read_miss, label_text);
            expect64(read_sample_count_out, count, {label_text, " count"});

            @(negedge clk);
            expect_true(!read_valid && !read_miss, {label_text, " response is one-cycle pulse"});
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        resetn = 1'b1;
        repeat (2) @(negedge clk);

        expect64(next_sample_count, 64'd0, "next sample count reset");
        expect64(oldest_sample_count, 64'd0, "oldest sample count reset");
        expect32(samples_retained, 32'd0, "retained count reset");
        expect_true(!read_valid && !read_miss, "read response reset");

        // A sample is not readable until it has been committed by a previous
        // edge; this also avoids BRAM read-during-write ambiguity.
        @(negedge clk);
        iq_in_re = 16'sd100;
        iq_in_im = -16'sd100;
        sample_valid = 1'b1;
        read_sample_count = 64'd0;
        read_req = 1'b1;
        @(negedge clk);
        sample_valid = 1'b0;
        read_req = 1'b0;
        expect_true(!read_valid && read_miss, "same-edge new sample is not yet readable");
        expect64(next_sample_count, 64'd1, "first accepted sample advances count");
        expect32(samples_retained, 32'd1, "first accepted sample retained");

        read_expect(64'd0, 16'sd100, -16'sd100, "committed first sample");

        // Gaps do not consume sample indices.
        idle_cycle();
        idle_cycle();
        expect64(next_sample_count, 64'd1, "idle cycles do not advance accepted-sample count");

        for (k = 1; k < DEPTH; k = k + 1)
            write_sample(16'sd100 + k, -(16'sd100 + k));

        expect64(next_sample_count, 64'd8, "buffer fills at eight accepted samples");
        expect64(oldest_sample_count, 64'd0, "oldest remains zero before wrap");
        expect32(samples_retained, 32'd8, "retained count saturates at depth");
        read_expect(64'd7, 16'sd107, -16'sd107, "latest sample before wrap");

        // Write sample 8 into physical address 0, evicting absolute sample 0.
        write_sample(16'sd108, -16'sd108);
        expect64(next_sample_count, 64'd9, "write pointer wraps in absolute sample domain");
        expect64(oldest_sample_count, 64'd1, "wrap evicts exactly one oldest sample");
        expect32(samples_retained, 32'd8, "retained count stays saturated after wrap");
        read_expect_miss(64'd0, "evicted absolute sample misses");
        read_expect(64'd1, 16'sd101, -16'sd101, "oldest retained sample after wrap");
        read_expect(64'd8, 16'sd108, -16'sd108, "wrapped physical address reads by absolute count");

        // With the full buffer, reading the oldest sample while the same RAM
        // address is overwritten is rejected deterministically.
        @(negedge clk);
        iq_in_re = 16'sd109;
        iq_in_im = -16'sd109;
        sample_valid = 1'b1;
        read_sample_count = 64'd1;
        read_req = 1'b1;
        @(negedge clk);
        sample_valid = 1'b0;
        read_req = 1'b0;
        expect_true(!read_valid && read_miss, "read/write collision is reported as miss");
        expect64(next_sample_count, 64'd10, "collision cycle still accepts new IQ sample");
        expect64(oldest_sample_count, 64'd2, "collision cycle advances retention window");
        read_expect(64'd9, 16'sd109, -16'sd109, "new sample is readable after collision cycle");

        // Streaming reset must realign the history epoch with the correlator.
        @(negedge clk);
        stream_reset = 1'b1;
        @(negedge clk);
        stream_reset = 1'b0;
        expect64(next_sample_count, 64'd0, "stream reset restarts accepted-sample epoch");
        expect64(oldest_sample_count, 64'd0, "stream reset clears oldest count");
        expect32(samples_retained, 32'd0, "stream reset clears retained occupancy");
        read_expect_miss(64'd9, "pre-reset history is outside new epoch");

        write_sample(16'sd777, -16'sd321);
        read_expect(64'd0, 16'sd777, -16'sd321, "post-reset sample starts at absolute zero");

        if (errors == 0)
            $display("PASS tb_lora_iq_history_buffer");
        else begin
            $display("FAIL tb_lora_iq_history_buffer errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule
