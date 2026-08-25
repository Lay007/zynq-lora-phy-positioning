`timescale 1ns/1ps

// LoRa receiver control-plane integration wrapper.
//
// This is deliberately a single-clock-domain building block. The accepted
// sample pulse, coarse-capture event, fractional ToA fragment, metadata joiner
// and AXI4-Lite register bank all run from s_axi_aclk. If the future receiver
// datapath uses another clock, the CDC boundary must be explicit outside this
// module.
//
// Data flow:
//   sample_valid -> 64-bit PL sample counter
//   coarse_capture -> captured coarse timestamp
//   captured coarse + fractional ToA
//          -> lora_timestamp_metadata_join
//          -> atomic metadata event
//          -> lora_axi_lite_status
//          -> PS-readable timestamp/status registers
//
// The sample counter is a timebase and is intentionally independent of
// receiver_enable. receiver_enable is reserved for gating the future receiver
// processing path, not for stopping timestamp progression.
//
// This wrapper does not yet instantiate generated LoRa DSP cores or an AD936x
// streaming interface. It is the control/metadata subsystem intended to be
// reused by that later receiver-level wrapper.
module lora_receiver_control_wrapper (
    input  wire                    s_axi_aclk,
    input  wire                    s_axi_aresetn,

    // Accepted-sample timebase and coarse timestamp capture event.
    // All signals are synchronous to s_axi_aclk.
    input  wire                    sample_valid,
    input  wire                    coarse_capture,

    // Fractional timestamp fragment from the ToA estimator.
    input  wire signed [31:0]      fractional_toa_q12,
    input  wire                    fractional_valid,

    // AXI4-Lite slave interface.
    input  wire [5:0]              s_axi_awaddr,
    input  wire                    s_axi_awvalid,
    output wire                    s_axi_awready,
    input  wire [31:0]             s_axi_wdata,
    input  wire [3:0]              s_axi_wstrb,
    input  wire                    s_axi_wvalid,
    output wire                    s_axi_wready,
    output wire [1:0]              s_axi_bresp,
    output wire                    s_axi_bvalid,
    input  wire                    s_axi_bready,

    input  wire [5:0]              s_axi_araddr,
    input  wire                    s_axi_arvalid,
    output wire                    s_axi_arready,
    output wire [31:0]             s_axi_rdata,
    output wire [1:0]              s_axi_rresp,
    output wire                    s_axi_rvalid,
    input  wire                    s_axi_rready,

    // Control output for the future receiver streaming wrapper.
    output wire                    receiver_enable
);

    wire [63:0]        live_sample_count;
    wire [63:0]        captured_coarse_sample_count;
    wire               captured_coarse_valid;

    wire [63:0]        timestamp_coarse;
    wire signed [31:0] timestamp_fractional_q12;
    wire               timestamp_valid;
    wire               metadata_overflow;

    lora_sample_counter_capture #(
        .COUNTER_WIDTH(64)
    ) sample_counter (
        .clk(s_axi_aclk),
        .resetn(s_axi_aresetn),
        .sample_valid(sample_valid),
        .capture(coarse_capture),
        .sample_count(live_sample_count),
        .captured_sample_count(captured_coarse_sample_count),
        .capture_valid(captured_coarse_valid)
    );

    lora_timestamp_metadata_join metadata_joiner (
        .clk(s_axi_aclk),
        .resetn(s_axi_aresetn),
        .coarse_sample_count(captured_coarse_sample_count),
        .coarse_valid(captured_coarse_valid),
        .fractional_toa_q12(fractional_toa_q12),
        .fractional_valid(fractional_valid),
        .timestamp_coarse(timestamp_coarse),
        .timestamp_fractional_q12(timestamp_fractional_q12),
        .timestamp_valid(timestamp_valid),
        .metadata_overflow(metadata_overflow)
    );

    lora_axi_lite_status status_registers (
        .s_axi_aclk(s_axi_aclk),
        .s_axi_aresetn(s_axi_aresetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .metadata_coarse(timestamp_coarse),
        .metadata_fractional_q12(timestamp_fractional_q12),
        .metadata_valid(timestamp_valid),
        .metadata_overflow(metadata_overflow),
        .receiver_enable(receiver_enable)
    );

endmodule
