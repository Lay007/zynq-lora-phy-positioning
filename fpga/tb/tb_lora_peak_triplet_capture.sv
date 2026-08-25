`timescale 1ns/1ps

module tb_lora_peak_triplet_capture;
    localparam integer SEARCH_SAMPLES = 7;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg resetn = 1'b0;
    reg search_start = 1'b0;
    reg [63:0] search_base_count = 64'd0;
    reg [31:0] magnitude = 32'd0;
    reg magnitude_valid = 1'b0;

    wire [31:0] magnitude_before;
    wire [31:0] magnitude_peak;
    wire [31:0] magnitude_after;
    wire [15:0] peak_index;
    wire [63:0] peak_sample_count;
    wire triplet_valid;
    wire busy;
    wire boundary_error;
    wire restart_error;

    integer errors = 0;

    lora_peak_triplet_capture #(
        .SEARCH_SAMPLES(SEARCH_SAMPLES)
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .search_start(search_start),
        .search_base_count(search_base_count),
        .magnitude(magnitude),
        .magnitude_valid(magnitude_valid),
        .magnitude_before(magnitude_before),
        .magnitude_peak(magnitude_peak),
        .magnitude_after(magnitude_after),
        .peak_index(peak_index),
        .peak_sample_count(peak_sample_count),
        .triplet_valid(triplet_valid),
        .busy(busy),
        .boundary_error(boundary_error),
        .restart_error(restart_error)
    );

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

    task automatic expect16(input [15:0] got, input [15:0] expected, input string label_text);
        begin
            if (got === expected)
                $display("PASS %-58s value=%0d", label_text, got);
            else begin
                errors = errors + 1;
                $display("FAIL %-58s got=%0d expected=%0d", label_text, got, expected);
            end
        end
    endtask

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

    task automatic start_with_first_sample(input [63:0] base_count, input [31:0] value);
        begin
            @(negedge clk);
            search_base_count = base_count;
            search_start = 1'b1;
            magnitude = value;
            magnitude_valid = 1'b1;
            @(negedge clk);
            search_start = 1'b0;
            magnitude_valid = 1'b0;
        end
    endtask

    task automatic send_sample(input [31:0] value);
        begin
            @(negedge clk);
            magnitude = value;
            magnitude_valid = 1'b1;
            @(negedge clk);
            magnitude_valid = 1'b0;
        end
    endtask

    task automatic wait_for_result;
        begin
            do begin
                @(posedge clk);
                #1;
            end while (!triplet_valid && !boundary_error);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        resetn = 1'b1;
        repeat (2) @(posedge clk);
        #1;

        expect_true(!busy, "busy reset");
        expect_true(!triplet_valid, "triplet valid reset");
        expect_true(!boundary_error, "boundary error reset");
        expect_true(!restart_error, "restart error reset");

        // Nominal search. Start and first magnitude deliberately share a cycle.
        // Idle clock gaps must not advance the sample index.
        start_with_first_sample(64'd1000, 32'd1);
        send_sample(32'd4);
        repeat (3) @(posedge clk);
        #1;
        expect_true(busy, "idle cycles keep search active");
        send_sample(32'd9);
        send_sample(32'd20);
        send_sample(32'd8);
        send_sample(32'd3);
        send_sample(32'd1);
        wait_for_result();

        expect32(magnitude_before, 32'd9, "nominal left neighbour");
        expect32(magnitude_peak, 32'd20, "nominal peak");
        expect32(magnitude_after, 32'd8, "nominal right neighbour");
        expect16(peak_index, 16'd3, "nominal peak index counts valid samples only");
        expect64(peak_sample_count, 64'd1003, "nominal peak sample count");
        expect_true(triplet_valid, "nominal triplet valid");
        expect_true(!boundary_error, "nominal search has no boundary error");

        @(posedge clk);
        #1;
        expect_true(!triplet_valid, "triplet valid is one-cycle pulse");

        // Equal maxima retain the first occurrence so timestamp behavior is
        // deterministic across implementations.
        start_with_first_sample(64'd2000, 32'd1);
        send_sample(32'd10);
        send_sample(32'd2);
        send_sample(32'd10);
        send_sample(32'd1);
        send_sample(32'd0);
        send_sample(32'd0);
        wait_for_result();
        expect16(peak_index, 16'd1, "first equal maximum wins");
        expect32(magnitude_before, 32'd1, "equal-max left neighbour");
        expect32(magnitude_peak, 32'd10, "equal-max peak");
        expect32(magnitude_after, 32'd2, "equal-max right neighbour");
        expect64(peak_sample_count, 64'd2001, "equal-max timestamp follows first maximum");

        @(posedge clk);
        #1;

        // A maximum at a search-window edge has no complete 3-point
        // neighbourhood and must not be passed to the ToA interpolator.
        start_with_first_sample(64'd3000, 32'd20);
        send_sample(32'd9);
        send_sample(32'd8);
        send_sample(32'd7);
        send_sample(32'd6);
        send_sample(32'd5);
        send_sample(32'd4);
        wait_for_result();
        expect_true(boundary_error, "boundary maximum is rejected");
        expect_true(!triplet_valid, "boundary maximum emits no triplet");

        @(posedge clk);
        #1;
        expect_true(!boundary_error, "boundary error is one-cycle pulse");

        // A second start while a window is active is rejected, but it must not
        // corrupt the original search.
        start_with_first_sample(64'd4000, 32'd1);
        send_sample(32'd2);
        @(negedge clk);
        search_base_count = 64'd9999;
        search_start = 1'b1;
        magnitude = 32'd3;
        magnitude_valid = 1'b1;
        @(posedge clk);
        #1;
        expect_true(restart_error, "restart while busy is reported");
        @(negedge clk);
        search_start = 1'b0;
        magnitude_valid = 1'b0;
        send_sample(32'd9);
        send_sample(32'd4);
        send_sample(32'd2);
        send_sample(32'd1);
        wait_for_result();
        expect16(peak_index, 16'd3, "rejected restart preserves original search");
        expect64(peak_sample_count, 64'd4003, "rejected restart preserves original base timestamp");

        if (errors == 0) begin
            $display("PASS tb_lora_peak_triplet_capture");
            $finish;
        end

        $display("FAIL tb_lora_peak_triplet_capture errors=%0d", errors);
        $fatal(1);
    end

endmodule
