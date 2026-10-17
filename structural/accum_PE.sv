// =============================================================================
// accum_PE.sv  --  one cell of the accumulation array (the "OR PE")
// -----------------------------------------------------------------------------
// Direct analog of top_PE, but the chain operation is OR instead of AND:
//   * top_PE  : and_gate folds this column into a running MATCH (seed = 1)
//   * accum_PE: or2     folds this row    into a running OR    (seed = 0)
//
// Each cell:
//   t_out     = register( t_in OR row_match_in )   -- the OR-reduction stage
//   valid_out = register( valid_in )               -- valid travels alongside,
//                                                     one delay per stage, so the
//                                                     OR cascade and the valid
//                                                     pipeline stay length-matched.
// Built from the same datapath primitives as accumulation_array_struct.
// =============================================================================
module accum_PE (
    input  logic clk,
    input  logic rst,

    input  logic t_in,          // running OR from the cell above (seed = 0 at the top)
    input  logic row_match_in,  // this row's match bit
    input  logic valid_in,      // valid token from the cell above

    output logic t_out,         // registered running OR  -> next cell down
    output logic valid_out      // delayed valid          -> next cell down
);

    // ----- OR this row into the running total, then register (the OR PE) -----
    logic or_result;
    or2 U_or  (
        .a (t_in),
        .b (row_match_in),
        .y (or_result)
    );
    dff U_treg (
        .clk (clk),
        .rst (rst),
        .d   (or_result),
        .q   (t_out)
    );

    // ----- Valid travels with the data, one register per stage --------------
    dff U_vreg (
        .clk (clk),
        .rst (rst),
        .d   (valid_in),
        .q   (valid_out)
    );

endmodule
