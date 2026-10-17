module top_PE #(
    parameter DATA_WIDTH = 8
) (
    input   logic   clk, rst, load_en, match_in, mask, a_valid_in,
    input   logic   [DATA_WIDTH-1:0] a_in, b_in,
    output  logic   [DATA_WIDTH-1:0] a_out, b_pass,
    output  logic   match_out, a_valid_out
);

    logic comp_out, and_output, mux_out, match_in_sig;
    logic [DATA_WIDTH-1:0] b_stored, a_in_sig, b_in_sig;

    
    assign a_in_sig = a_out;
    assign b_in_sig = b_in;
    assign match_in_sig = match_in;

    
    areg #(
        .DATA_WIDTH(DATA_WIDTH)
    ) U_areg (
        .clk,
        .rst,
        .a_in,
        .a_out,
        .a_valid_in,
        .a_valid_out
    );

    breg #(
        .DATA_WIDTH(DATA_WIDTH)
    ) U_breg (
        .clk,
        .rst,
        .load_en,
        .b_in,
        .b_pass(b_stored)
    );

    assign b_pass = b_stored;

    match_out_reg U_match_out_reg (
        .clk,
        .rst,
        .mux_out(mux_out),
        .match_out
    );

    comparator #(
        .DATA_WIDTH(DATA_WIDTH)
    ) U_comparator (
        .a_in(a_in_sig),
        .b_in(b_stored),
        .a_valid_in(a_valid_out),
        .comp_out(comp_out)
    );

    and_gate U_and_gate (
        .comp_out(comp_out),
        .match_in(match_in_sig),
        .and_output(and_output)
    );

    mux U_mux (
        .mask,
        .and_output,
        .match_in,
        .mux_out(mux_out)
    );

    
endmodule