// =============================================================================
// accumulation_array_pe.sv
// -----------------------------------------------------------------------------
// PE-array style build of the accumulation array, mirroring pe_array_2d:
//   * a vertical "cascade highway" runs through the column of cells
//   * a generate loop stamps out NUM_ROWS identical accum_PE cells
//   * the highway is SEEDED at the ceiling -- with 0 (OR identity), exactly as
//     pe_row seeds its match chain with 1 (AND identity)
//
// Logically identical to accumulation_array.sv / accumulation_array_struct.sv
// (proven cycle-for-cycle in tb_accum_pe_equiv.sv). Use this version when you
// want the datapath drawn as a column of PEs, just like the 2D array.
// =============================================================================
module accumulation_array_pe #(
    parameter NUM_ROWS = 50
)(
    input  logic                clk,
    input  logic                rst,
    input  logic [NUM_ROWS-1:0] row_match_out,
    input  logic                valid_in,
    input  logic                accum_mode,

    output logic                t_i,
    output logic                valid_out
);

    // =========================================================================
    // CASCADE HIGHWAYS  (analog of a_cascade / a_valid_cascade in pe_array_2d)
    //   index [0]        = the ceiling above cell 0
    //   index [NUM_ROWS] = the floor beneath the last cell
    // =========================================================================
    logic [NUM_ROWS:0] t_cascade;   // running OR travelling down the column
    logic [NUM_ROWS:0] v_cascade;   // valid token travelling down alongside

    // ----- SEED THE TOP OF THE HIGHWAY --------------------------------------
    assign t_cascade[0] = 1'b0;       // OR identity (mirror of pe_row's match_in = 1'b1)
    assign v_cascade[0] = valid_in;   // the valid token enters at the ceiling

    // =========================================================================
    // THE COLUMN OF OR-PEs  (analog of the ROW_FACTORY generate loop)
    //   cell i pulls from ceiling i and drops to floor i+1
    // =========================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_ROWS; i++) begin : ACCUM_PE
            accum_PE U_pe (
                .clk          (clk),
                .rst          (rst),
                .t_in         (t_cascade[i]),       // running OR from above
                .row_match_in (row_match_out[i]),   // this row's match bit
                .valid_in     (v_cascade[i]),       // valid from above
                .t_out        (t_cascade[i+1]),     // running OR to below
                .valid_out    (v_cascade[i+1])      // valid to below
            );
        end
    endgenerate

    // =========================================================================
    // MODE SELECT  --  OR (intersection) vs NOR (difference)
    //   final OR result falls out of the floor of the highway.
    // =========================================================================
    logic final_or, final_nor;
    assign final_or = t_cascade[NUM_ROWS];

    inv  U_inv  (
        .a (final_or),
        .y (final_nor)
    );
    mux2 U_mode (
        .sel (accum_mode),   // 0 = intersection, 1 = difference
        .d0  (final_or),     // OR
        .d1  (final_nor),    // NOR
        .y   (t_i)
    );

    // valid token that exits the floor is the final, length-matched strobe.
    assign valid_out = v_cascade[NUM_ROWS];

endmodule
