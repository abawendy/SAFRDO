module output_router #(
    parameter NUM_ROWS = 50 // Kept consistent with your Accumulator
)(
    // ==========================================
    // DATA INPUTS (From internal datapath)
    // ==========================================
    input  logic [NUM_ROWS-1:0] row_match_in,          // From 2D Array
    input  logic [NUM_ROWS-1:0] a_valid_vector_in, // From 2D Array

    input  logic                t_i,                   // From Accumulator
    input  logic                accum_valid_in,        // From Accumulator

    input  logic [NUM_ROWS-1:0] row_data_in,           // From Join Collector (one B-row's match vector)

    // ==========================================
    // CONTROL INPUT (The lever to switch modes)
    // ==========================================
    // 2'b00 = Vector (Selection), 2'b01 = Scalar (Intersection/Difference),
    // 2'b10 = Join (one B-row match vector per read address)
    input  logic [1:0]          out_sel,

    // ==========================================
    // FINAL UNIFIED OUTPUTS (To the CPU)
    // ==========================================
    output logic [NUM_ROWS-1:0] final_data_out,
    output logic [NUM_ROWS-1:0] final_valid_out
);

    always_comb begin
        unique case (out_sel)
            // ------------------------------------------
            // SCALAR MODE (out_sel = 2'b01) -- Intersection / Difference
            // ------------------------------------------
            // Pad the 1-bit scalar signals with (NUM_ROWS-1) zeros.
            // The result becomes the Least Significant Bit (LSB).
            2'b01: begin
                final_data_out  = { {(NUM_ROWS-1){1'b0}}, t_i };
                final_valid_out = { {(NUM_ROWS-1){1'b0}}, accum_valid_in };
            end

            // ------------------------------------------
            // JOIN MODE (out_sel = 2'b10) -- one B-row match vector
            // ------------------------------------------
            // The bridge addresses a B-row via the collector's row_sel; that row's
            // full match vector arrives here. The bridge reads it directly (it walks
            // the rows itself), so no valid strobe is needed on this path.
            2'b10: begin
                final_data_out  = row_data_in;
                final_valid_out = '0;
            end

            // ------------------------------------------
            // VECTOR MODE (out_sel = 2'b00, default) -- Selection
            // ------------------------------------------
            // Pass the full NUM_ROWS vector buses directly.
            default: begin
                final_data_out  = row_match_in;
                final_valid_out = a_valid_vector_in;
            end
        endcase
    end

endmodule
