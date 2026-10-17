module safrdo_datapath #(
    parameter NUM_ROWS = 50,
    parameter DATA_WIDTH = 32,
    parameter NUM_COLS = 4,
    // ----- Derived width (do not override) ------------------------------------
    parameter int IDX_W = $clog2(NUM_ROWS)   // bits for one row index (6 @50)
)(
    input  logic clk,
    input  logic rst,

    // ==========================================
    // 1. DATA INPUTS (From BRAM Memory)
    // ==========================================
    input  logic [DATA_WIDTH-1:0] bram_table_a_data,
    input  logic [DATA_WIDTH-1:0] bram_table_b_data,

    // ==========================================
    // 2. CONTROL INPUTS (Dangling wires for the Brain)
    // ==========================================
    input  logic [1:0] opcode_in,
    input  logic [3:0] mask_in,
    input  logic [7:0] imm_in,
    
    input  logic       sel_data_A,   // 1 = Aligner, 0 = BRAM A
    input  logic       load_en,  // 1 = Load B, 0 = Execute
    input  logic       array_valid_in, // Triggers the math
    input  logic [1:0] out_sel,        // 00 = Vector, 01 = Scalar, 10 = Join
    input  logic       accum_mode,

    // ----- Join collector control ---------------------------------------------
    input  logic              join_clear,    // per-instruction matrix soft reset
    input  logic [IDX_W-1:0]  join_row_sel,  // which B-row the bridge is reading

    // ==========================================
    // 3. FINAL OUTPUTS (To Host CPU)
    // ==========================================
    output logic [NUM_ROWS-1:0] final_data_out,
    output logic [NUM_ROWS-1:0] final_valid_out
);

    // ==========================================
    // INTERNAL WIRES (The copper traces on the motherboard)
    // ==========================================
    logic [DATA_WIDTH-1:0] aligned_data_wire;
    logic [DATA_WIDTH-1:0] mux_to_array_wire;
    
    logic [NUM_ROWS-1:0]   row_match_wire;
    logic [NUM_ROWS-1:0]   array_valid_wire;
    
    logic                  t_i_wire;
    logic                  accum_valid_wire;

    logic [NUM_ROWS-1:0]   row_data_wire;   // one B-row's match vector, from the collector

    // ==========================================
    // MODULE INSTANTIATIONS (Snapping the LEGOs together)
    // ==========================================

    // 1. The Aligner
    operand_aligner my_aligner (
        .opcode      (opcode_in),
        .mask        (mask_in),
        .imm_in      (imm_in),
        .aligned_out (aligned_data_wire)
    );

    // 2. The Data MUX (Simple combinational routing)
    assign mux_to_array_wire = sel_data_A ? aligned_data_wire : bram_table_a_data;

    
    localparam PE_WIDTH  = 8; 

    // Create 2D wires that perfectly match the pe_array_2d input ports
    logic [NUM_COLS-1:0][PE_WIDTH-1:0] grid_A_wire;
    logic [NUM_COLS-1:0][PE_WIDTH-1:0] grid_B_wire;

    // Use a generate loop to safely slice the 32-bit 1D wire into the 2D grid
    genvar c;
    generate
        for (c = 0; c < NUM_COLS; c++) begin : SLICE_DATA
            // This chops [31:0] into four [7:0] chunks
            assign grid_A_wire[c] = mux_to_array_wire[(c*PE_WIDTH) +: PE_WIDTH];
            assign grid_B_wire[c] = bram_table_b_data[(c*PE_WIDTH) +: PE_WIDTH];
        end
    endgenerate

    // 3. The 2D Systolic Array (The Math Core)
    pe_array_2d #(
        .NUM_ROWS (NUM_ROWS),
        .DATA_WIDTH (8),
        .NUM_COLS(NUM_COLS) 
    ) my_2d_array (
        .clk        (clk),
        .rst        (rst),
        .A_in_flat       (grid_A_wire), // Comes from the MUX
        .B_in_flat       (grid_B_wire), // Comes direct from BRAM
        .mask       (mask_in),           // The smart mask from Controller
        .load_en    (load_en),
        .valid_in   (array_valid_in),
        .row_match_out  (row_match_wire),    // Goes to Router AND Accumulator
        .a_valid_vector_out  (array_valid_wire)  // Goes to Router AND Accumulator
        // .A_out      (), // Left unconnected (Data Exhaust)
        // .B_out      ()  // Left unconnected (Data Exhaust)
    );

    // 4. The Accumulator Array (The Scalar Reducer) -- PE-array build: a column
    //    of accum_PE cells (or2 + dff), the OR-chain analog of the 2D AND-array.
    accumulation_array_pe #(
        .NUM_ROWS (NUM_ROWS)
    ) my_accum (
        .clk           (clk),
        .rst           (rst),
        .row_match_out (row_match_wire), // Taps into 2D array output
        .valid_in      (array_valid_wire[0]), // Taps into 2D array output
        .t_i           (t_i_wire),         // Goes to Router
        .valid_out     (accum_valid_wire),  // Goes to Router
        .accum_mode    (accum_mode)
    );

    // The accumulator asserts its valid one cycle BEFORE t_i settles. Delay the
    // valid here (in the datapath) so it lands aligned with the settled t_i and
    // the bridge sees a clean strobe -- this REPLACES the old bridge-side valid_d
    // resample, keeping all latency compensation inside the main architecture.
    logic accum_valid_d;
    always_ff @(posedge clk) begin
        if (rst) accum_valid_d <= 1'b0;
        else     accum_valid_d <= accum_valid_wire;
    end

    // 5. The Join Collector (Pure-datapath match-matrix capture + row read port)
    //    Taps the SAME wires as the accumulator; the bridge addresses one B-row
    //    at a time via row_sel during read-out. No FSM here.
    join_collector #(
        .NUM_ROWS (NUM_ROWS)
    ) my_collector (
        .clk             (clk),
        .rst             (rst),
        .clear           (join_clear),
        .row_match_in    (row_match_wire),   // same tap as accumulator
        .valid_vector_in (array_valid_wire), // full per-row valid vector
        .row_sel         (join_row_sel),     // bridge-driven read address
        .row_data_out    (row_data_wire)     // selected row's match vector -> Router
    );

    // 6. The Output Router (The Final Switchboard)
    output_router #(
        .NUM_ROWS (NUM_ROWS)
    ) my_router (
        .row_match_in          (row_match_wire),
        .a_valid_vector_in (array_valid_wire),
        .t_i                   (t_i_wire),
        .accum_valid_in        (accum_valid_d),   // aligned strobe (see above)
        .row_data_in           (row_data_wire),
        .out_sel               (out_sel),
        .final_data_out        (final_data_out),
        .final_valid_out       (final_valid_out)
    );

endmodule