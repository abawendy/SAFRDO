module pe_row #(
    parameter DATA_WIDTH = 8
) (
    input  logic clk, 
    input  logic rst, 
    input  logic load_en,
    // Incoming Valid Bits (Flowing Top-Down)
    input  logic a_valid_in_0, a_valid_in_1, a_valid_in_2, a_valid_in_3,

    // Outgoing Valid Bits (Passing down to the next row)
    output logic a_valid_out_0, a_valid_out_1, a_valid_out_2, a_valid_out_3,
    
    // The 4-bit global mask from the Control Unit
    input  logic [3:0] mask, 

    // Incoming Tuple A (4 distinct attributes from the stream above)
    input  logic [DATA_WIDTH-1:0] a_in_0, a_in_1, a_in_2, a_in_3,
    
    // Incoming Tuple B (from the row below during Load Phase)
    input  logic [DATA_WIDTH-1:0] b_in_0, b_in_1, b_in_2, b_in_3,

    // Outgoing Tuple A (passing down to the next row)
    output logic [DATA_WIDTH-1:0] a_out_0, a_out_1, a_out_2, a_out_3,
    
    // Outgoing Tuple B (passing up to the next row during Load Phase)
    output logic [DATA_WIDTH-1:0] b_pass_0, b_pass_1, b_pass_2, b_pass_3,

    // The single, final definitive match signal for the whole tuple
    output logic row_match_out
);

    // ==========================================
    // INTERNAL WIRES (The Ripple Cascade)
    // ==========================================
    logic match_c0_to_c1;
    logic match_c1_to_c2;
    logic match_c2_to_c3;

    

    // ==========================================
    // COLUMN 0
    // ==========================================
    top_PE #(.DATA_WIDTH(DATA_WIDTH)) PE_Col0 (
        .clk(clk), 
        .rst(rst), 
        .load_en(load_en),
        .mask(mask[0]),       // Taps into bit 0 of the global mask
        .match_in(1'b1),      // CRITICAL: First PE is always hardwired to TRUE
        .a_valid_in(a_valid_in_0), 
        .a_in(a_in_0), 
        .b_in(b_in_0),
        .a_valid_out(a_valid_out_0), // Passes valid bit down to Column 1
        .a_out(a_out_0), 
        .b_pass(b_pass_0),
        .match_out(match_c0_to_c1) // Sends match result to Column 1
    );

    // ==========================================
    // COLUMN 1
    // ==========================================
    top_PE #(.DATA_WIDTH(DATA_WIDTH)) PE_Col1 (
        .clk(clk), 
        .rst(rst), 
        .load_en(load_en),
        .mask(mask[1]),       // Taps into bit 1 of the global mask
        .match_in(match_c0_to_c1), // Receives match result from Column 0
        .a_valid_in(a_valid_in_1), 
        .a_in(a_in_1), 
        .b_in(b_in_1),
        .a_valid_out(a_valid_out_1),
        .a_out(a_out_1), 
        .b_pass(b_pass_1),
        .match_out(match_c1_to_c2) // Sends match result to Column 2
    );

    // ==========================================
    // COLUMN 2
    // ==========================================
    top_PE #(.DATA_WIDTH(DATA_WIDTH)) PE_Col2 (
        .clk(clk), 
        .rst(rst), 
        .load_en(load_en),
        .mask(mask[2]),       // Taps into bit 2 of the global mask
        .match_in(match_c1_to_c2), // Receives match result from Column 1
        .a_valid_in(a_valid_in_2),
        .a_in(a_in_2), 
        .b_in(b_in_2),
        .a_valid_out(a_valid_out_2),
        .a_out(a_out_2), 
        .b_pass(b_pass_2),
        .match_out(match_c2_to_c3) // Sends match result to Column 3
    );

    // ==========================================
    // COLUMN 3 (Final Column)
    // ==========================================
    top_PE #(.DATA_WIDTH(DATA_WIDTH)) PE_Col3 (
        .clk(clk), 
        .rst(rst), 
        .load_en(load_en),
        .mask(mask[3]),       // Taps into bit 3 of the global mask
        .match_in(match_c2_to_c3), // Receives match result from Column 2
        .a_valid_in(a_valid_in_3),
        .a_in(a_in_3), 
        .b_in(b_in_3),
        .a_valid_out(a_valid_out_3),
        .a_out(a_out_3), 
        .b_pass(b_pass_3),
        .match_out(row_match_out)  // Sends the final answer out of the row module
    );

endmodule