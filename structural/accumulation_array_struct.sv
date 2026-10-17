// =============================================================================
// accumulation_array_struct.sv
// -----------------------------------------------------------------------------
// STRUCTURAL twin of accumulation_array.sv. Logically identical (proven cycle-
// for-cycle in tb_accum_equiv.sv) but built entirely from named primitives --
// dff / or2 / inv / mux2 -- so the elaborated schematic shows clean, labelled
// boxes that map one-to-one onto a datapath drawing. Use this version for the
// report figures; the behavioural original stays the synthesis source.
//
// Two length-matched pipelines, exactly as in the behavioural model:
//   TOP   : OR-reduction cascade -> mode select (OR=intersection / NOR=difference) -> t_i
//   BOTTOM: valid shift register (same depth) -> valid_out
// =============================================================================
module accumulation_array_struct #(
    parameter NUM_ROWS = 4
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
    // TOP PIPELINE -- cascaded OR-reduction (one or2 + one dff per stage)
    //   t_chain[0]   = reg( row_match_out[0] )
    //   t_chain[i]   = reg( t_chain[i-1] | row_match_out[i] )
    // =========================================================================
    logic [NUM_ROWS-1:0] or_result;   // combinational OR feeding each stage
    logic [NUM_ROWS-1:0] t_chain;      // registered partial-OR chain

    // Stage 0: nothing to OR yet, just register the first row's match.
    dff U_t_chain0 (
        .clk (clk),
        .rst (rst),
        .d   (row_match_out[0]),
        .q   (t_chain[0])
    );

    genvar i;
    generate
        for (i = 1; i < NUM_ROWS; i++) begin : ACCUM_STAGE
            or2 U_or (
                .a (t_chain[i-1]),
                .b (row_match_out[i]),
                .y (or_result[i])
            );
            dff U_reg (
                .clk (clk),
                .rst (rst),
                .d   (or_result[i]),
                .q   (t_chain[i])
            );
        end
    endgenerate

    // =========================================================================
    // MODE SELECT -- OR (intersection) vs NOR (difference)
    //   t_i = accum_mode ? ~final_or : final_or
    // =========================================================================
    logic final_or;     // = t_chain[NUM_ROWS-1]
    logic final_nor;    // = ~final_or  (difference path)

    assign final_or = t_chain[NUM_ROWS-1];

    inv U_inv (
        .a (final_or),
        .y (final_nor)
    );

    mux2 U_mode (
        .sel (accum_mode),   // 0 = intersection, 1 = difference
        .d0  (final_or),     // OR
        .d1  (final_nor),    // NOR
        .y   (t_i)
    );

    // =========================================================================
    // BOTTOM PIPELINE -- valid shift register, length-matched to the OR cascade
    //   valid_shift[0] = reg( valid_in )
    //   valid_shift[i] = reg( valid_shift[i-1] )
    //   valid_out      = valid_shift[NUM_ROWS-1]
    // =========================================================================
    logic [NUM_ROWS-1:0] valid_shift;

    dff U_valid0 (
        .clk (clk),
        .rst (rst),
        .d   (valid_in),
        .q   (valid_shift[0])
    );

    generate
        for (i = 1; i < NUM_ROWS; i++) begin : VALID_STAGE
            dff U_vreg (
                .clk (clk),
                .rst (rst),
                .d   (valid_shift[i-1]),
                .q   (valid_shift[i])
            );
        end
    endgenerate

    assign valid_out = valid_shift[NUM_ROWS-1];

endmodule
