module stagger_module #(
    parameter DATA_WIDTH = 8,
    parameter NUM_COLS   = 4
)(
    input  logic                                 clk,
    input  logic                                 reset,
    
    input  logic [NUM_COLS-1:0][DATA_WIDTH-1:0]  A_in,
    input  logic                                 valid_in,
 
    output logic [NUM_COLS-1:0][DATA_WIDTH-1:0]  A_out,
    output logic [NUM_COLS-1:0]                  a_valid // <-- CHANGED TO VECTOR
);
    genvar i;
    generate
        for (i = 0; i < NUM_COLS; i++) begin : stagger
            if (i == 0) begin : one_cycle_delay
                // Column 0: 1 cycle delay (registered)
                always_ff @(posedge clk or posedge reset) begin
                    if (reset) A_out[0] <= '0;
                    else       A_out[0] <= A_in[0];
                end
            end
            else begin : shift_delay
                // Column i: i+1 cycles delay
                logic [DATA_WIDTH-1:0] shift_reg [0:i-1];
                integer k;
 
                always_ff @(posedge clk or posedge reset) begin
                    if (reset) begin
                        for (k = 0; k < i; k++)
                            shift_reg[k] <= '0;
                        A_out[i] <= '0;
                    end
                    else begin
                        shift_reg[0] <= A_in[i];
                        for (k = 1; k < i; k++)
                            shift_reg[k] <= shift_reg[k-1];
                        A_out[i] <= shift_reg[i-1];
                    end
                end
            end
        end
    endgenerate
 
    // ==========================================
    // STAGGER THE VALID BITS 
    // ==========================================
    // col0 gets 1 cycle delay, col1 gets 2, etc.
    logic [NUM_COLS-1:0] valid_shift;
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            valid_shift <= '0;
        else
            valid_shift <= {valid_shift[NUM_COLS-2:0], valid_in}; // Shift left
    end
 
    // Wire each column's valid bit to its exact matching delay stage
    assign a_valid[0] = valid_shift[0]; // Delayed 1 cycle
    assign a_valid[1] = valid_shift[1]; // Delayed 2 cycles
    assign a_valid[2] = valid_shift[2]; // Delayed 3 cycles
    assign a_valid[3] = valid_shift[3]; // Delayed 4 cycles
 
endmodule