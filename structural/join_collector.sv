// =============================================================================
// join_collector.sv
// -----------------------------------------------------------------------------
// JOIN result store for SAFRDO (opcode 01). Pure DATAPATH block, sibling to
// accumulation_array. Captures the FULL N x N match matrix exactly as before,
// but exposes it through a ROW read port instead of a single-cell cursor:
// the bridge addresses one B-row at a time and reads its whole 50-bit match
// vector, then expands it into (A_idx, B_idx) pairs on the host.
//
// This replaces the old 2,500:1 single-bit read mux (sr[b_sel][p_sel]) with a
// 50:1 word mux (sr[row_sel]) -- deleting every F7/F8 wide-mux in the design
// and the entire DRAIN sweep -- while the shift-register capture is unchanged.
//
// CAPTURE (structural, runs whenever a row's valid is high):
//   One shift register per resident B-row. As Table A streams past, each B-row
//   shifts in its own match bit (row_match_in[b]) when its own valid is high
//   (valid_vector_in[b]). Each row owns its register AND its valid, so the
//   systolic diagonal skew is absorbed automatically -- no deskew network.
//   After streaming:  sr[b][p] = match( A_{n_a-1-p} , B_b )
//   (newest A-row sits at bit 0; oldest, A_0, sits at bit n_a-1).
//
// READ PORT (combinational, addressed by the bridge, UART-paced):
//   row_data_out = sr[row_sel]  -- the full match vector of B-row row_sel.
//   The host reads num_b_rows of these vectors and, for row b, emits a pair
//   (A = n_a-1-p, B = b) for every set bit p < n_a.
//
// The matrix persists after DONE (only 'clear' at the next instruction wipes
// it), so the slow UART read-out is safe.
// =============================================================================

module join_collector #(
    parameter int NUM_ROWS = 50,                  // N : max rows of A and of B
    // ----- Derived width (do not override) ------------------------------------
    parameter int IDX_W  = $clog2(NUM_ROWS)       // bits for one row index (6 @50)
)(
    input  logic clk,
    input  logic rst,

    // ----- Per-instruction soft reset (from controller, at op start) ----------
    input  logic clear,

    // ----- Match stream taps (same wires the accumulator taps) ----------------
    input  logic [NUM_ROWS-1:0] row_match_in,     // per-B-row match bit, this cycle
    input  logic [NUM_ROWS-1:0] valid_vector_in,  // per-B-row valid (skew-aligned)

    // ----- Row read port (addressed by the bridge during read-out) ------------
    input  logic [IDX_W-1:0]    row_sel,          // which B-row to read

    // ----- Result (to output_router, then final_data_out) ---------------------
    output logic [NUM_ROWS-1:0] row_data_out       // full match vector of B-row row_sel
);

    // =========================================================================
    // CAPTURE -- one shift register per B-row (structural, no FSM)
    //   sr[b] fills with B-row b's match stream in A-arrival order.
    // =========================================================================
    logic [NUM_ROWS-1:0] sr [NUM_ROWS];

    // The array's per-row valid leads its match data by one cycle (same skew the
    // accumulator compensates with accum_valid_d). Delay the shift-enable by one
    // cycle so each match bit is captured AFTER it settles -- otherwise the first
    // shift grabs junk and the last A-row is dropped. Pure pipeline reg, no FSM.
    logic [NUM_ROWS-1:0] valid_d;
    always_ff @(posedge clk) begin
        if (rst || clear) valid_d <= '0;
        else              valid_d <= valid_vector_in;
    end

    genvar gb;
    generate
        for (gb = 0; gb < NUM_ROWS; gb++) begin : CAP_SR
            always_ff @(posedge clk) begin
                if (rst || clear)
                    sr[gb] <= '0;
                else if (valid_d[gb])
                    sr[gb] <= {sr[gb][NUM_ROWS-2:0], row_match_in[gb]};
            end
        end
    endgenerate

    // =========================================================================
    // READ PORT -- one whole row per address (50:1 word mux, not 2,500:1 bit mux)
    // =========================================================================
    assign row_data_out = sr[row_sel];

endmodule
