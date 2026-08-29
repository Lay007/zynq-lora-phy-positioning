`timescale 1ns/1ps

// Quantized complex reference chirp used by the packet-rate matched filter.
//
// Each memory word is {signed Q10 real, signed Q10 imaginary}. The default
// image is the authoritative SF7/L=8 upchirp exported from the MATLAB/Python
// convention shared by this repository. A synchronous output would add an
// address/response stage to lora_matched_filter_mac; the current combinational
// read is deliberately matched to that engine's ISSUE-cycle contract.
module lora_reference_chirp_rom #(
    parameter integer REF_SAMPLES = 1024,
    parameter INIT_FILE = "fpga/rom/lora_sf7_l8_reference_q10.mem"
) (
    input  wire [15:0]              reference_index,
    output wire signed [15:0]       reference_re,
    output wire signed [15:0]       reference_im
);

    (* rom_style = "block" *) reg [31:0] reference_mem [0:REF_SAMPLES-1];
    wire [31:0] reference_word = reference_mem[reference_index];

    initial begin
        if (REF_SAMPLES < 1 || REF_SAMPLES > 65535)
            $error("lora_reference_chirp_rom REF_SAMPLES must be 1..65535");
        $readmemh(INIT_FILE, reference_mem);
    end

    assign reference_re = $signed(reference_word[31:16]);
    assign reference_im = $signed(reference_word[15:0]);

endmodule

