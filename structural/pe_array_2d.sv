module pe_array_2d #(
    parameter NUM_ROWS = 50,
    parameter NUM_COLS = 4,
    parameter DATA_WIDTH = 8
)(
    // Global Control Signals
    input  logic clk,
    input  logic rst,
    input  logic load_en,
    input  logic valid_in,
    input  logic [NUM_COLS-1:0] mask,
    
    // Flat Data Inputs from the Host CPU
    input  logic [NUM_COLS-1:0][DATA_WIDTH-1:0] A_in_flat,
    input  logic [NUM_COLS-1:0][DATA_WIDTH-1:0] B_in_flat, 
    
    // Outputs back to the Host CPU
    output logic [NUM_ROWS-1:0] a_valid_vector_out,
    output logic [NUM_ROWS-1:0] row_match_out // 50 individual match wires
);

    // ==========================================
    // 1. THE VERTICAL CASCADING HIGHWAYS
    // ==========================================
    // Index [0] is the ceiling above Row 0.
    // Index [NUM_ROWS] is the floor beneath the bottom Row.
    logic [NUM_ROWS:0][NUM_COLS-1:0][DATA_WIDTH-1:0] a_cascade;
    logic [NUM_ROWS:0][NUM_COLS-1:0][DATA_WIDTH-1:0] b_cascade;
    logic [NUM_ROWS:0][NUM_COLS-1:0] a_valid_cascade;

    // Connect the flat B input to the FLOOR of the B highway (Bottom-Up)
    assign b_cascade[NUM_ROWS] = B_in_flat;

    
    

    // ==========================================
    // 2. THE STAGGER MODULE (Top of the Array)
    // ==========================================
    stagger_module #(
        .NUM_COLS(NUM_COLS),
        .DATA_WIDTH(DATA_WIDTH)
    ) U_Stagger (
        .clk(clk),
        .reset(rst),
        .A_in(A_in_flat),
        .valid_in(valid_in),
        // The staggered A output drops onto the CEILING of the A highway (Top-Down)
        .A_out(a_cascade[0]), 
        .a_valid(a_valid_cascade[0]) // Initializes the valid cascade at the top
    );

    // ==========================================
    // 3. THE 50x4 SYSTOLIC ARRAY FACTORY
    // ==========================================
    genvar i;
    generate
        for (i = 0; i < NUM_ROWS; i++) begin : ROW_FACTORY
            
            pe_row #(
                .DATA_WIDTH(DATA_WIDTH)
            ) U_Row (
                .clk(clk),
                .rst(rst),
                .load_en(load_en),
                .mask(mask),
                // -----------------------------------------
                // VALID BITS CASCADING (Flows Top-Down)
                // -----------------------------------------
                .a_valid_in_0 (a_valid_cascade[i][0]),
                .a_valid_in_1 (a_valid_cascade[i][1]),
                .a_valid_in_2 (a_valid_cascade[i][2]),
                .a_valid_in_3 (a_valid_cascade[i][3]),

                .a_valid_out_0(a_valid_cascade[i+1][0]),
                .a_valid_out_1(a_valid_cascade[i+1][1]),
                .a_valid_out_2(a_valid_cascade[i+1][2]),
                .a_valid_out_3(a_valid_cascade[i+1][3]),

                // -----------------------------------------
                // TUPLE A CASCADING (Flows Top-Down)
                // Row 'i' pulls from ceiling 'i' and drops to floor 'i+1'
                // -----------------------------------------
                .a_in_0(a_cascade[i][0]),
                .a_in_1(a_cascade[i][1]),
                .a_in_2(a_cascade[i][2]),
                .a_in_3(a_cascade[i][3]),
                
                .a_out_0(a_cascade[i+1][0]),
                .a_out_1(a_cascade[i+1][1]),
                .a_out_2(a_cascade[i+1][2]),
                .a_out_3(a_cascade[i+1][3]),

                // -----------------------------------------
                // RELATION B CASCADING (Flows Bottom-Up)
                // Row 'i' pulls from floor 'i+1' and pushes to ceiling 'i'
                // -----------------------------------------
                .b_in_0(b_cascade[i+1][0]),
                .b_in_1(b_cascade[i+1][1]),
                .b_in_2(b_cascade[i+1][2]),
                .b_in_3(b_cascade[i+1][3]),
                
                .b_pass_0(b_cascade[i][0]),
                .b_pass_1(b_cascade[i][1]),
                .b_pass_2(b_cascade[i][2]),
                .b_pass_3(b_cascade[i][3]),

                // -----------------------------------------
                // HORIZONTAL MATCH SIGNAL
                // -----------------------------------------
                .row_match_out(row_match_out[i])
            );
            
        end
    endgenerate

    // ==================================================
    // VALID VECTOR SYNCHRONIZATION
    // ==================================================
    genvar j;
    generate
        for (j = 0; j < NUM_ROWS; j++) begin : VALID_DELAY
            // The valid bit drops vertically instantly, but the match data 
            // takes NUM_COLS cycles to cross the row horizontally.
            // We must delay the valid bit by NUM_COLS to align them!
            logic [NUM_COLS-1:0] valid_shift;

            always_ff @(posedge clk) begin
                if (rst) 
                    valid_shift <= '0;
                else     
                    valid_shift <= {valid_shift[NUM_COLS-2:0], a_valid_cascade[j+1][0]};
            end

            // Tap the end of the shift register so it pops out at the exact 
            // same time the data finishes crossing the row.
            assign a_valid_vector_out[j] = valid_shift[NUM_COLS-2]; 
        end
    endgenerate

   
endmodule