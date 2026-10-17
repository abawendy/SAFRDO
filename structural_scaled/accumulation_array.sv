module accumulation_array #(
    parameter NUM_ROWS = 4
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic [NUM_ROWS-1:0]   row_match_out,
    input  logic                  valid_in, accum_mode,

    output logic                  t_i,
    output logic                  valid_out
);

    // =======================================================
    // 1. THE MATH PIPELINE (Cascading OR-gate tree)
    // =======================================================
    logic [NUM_ROWS-1:0] t_chain;

    // Stage 0: Latch the first row's match result
    always_ff @(posedge clk) begin
        if (rst) 
            t_chain[0] <= 1'b0;
        else     
            t_chain[0] <= row_match_out[0];
    end

    // Stages 1 to NUM_ROWS-1: Cascade the OR logic
    genvar i;
    generate
        for (i = 1; i < NUM_ROWS; i++) begin : ACCUM_STAGE
            always_ff @(posedge clk) begin
                if (rst) 
                    t_chain[i] <= 1'b0;
                else     
                    t_chain[i] <= t_chain[i-1] | row_match_out[i];
            end
        end
    endgenerate

    // 1. Declare the wire and pull the final result from the OR-chain
    logic final_or_result;
    assign final_or_result = t_chain[NUM_ROWS-1];

    // 2. Drive t_i EXACTLY ONCE based on the mode
    always_comb begin
        if (accum_mode) begin 
            t_i = ~final_or_result;  // 1 = DIFFERENCE (Invert to NOR)
        end else begin           
            t_i = final_or_result;   // 0 = INTERSECTION (Keep as OR)
        end
    end


    // =======================================================
    // 2. THE VALID PIPELINE (Parallel Shift Register)
    // =======================================================
    logic [NUM_ROWS-1:0] valid_shift;

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_shift <= '0; // Clear the entire shift register on reset
        end else begin
            // Shift all bits left by 1, and pull valid_in into the first slot
            valid_shift <= {valid_shift[NUM_ROWS-2:0], valid_in}; 
        end
    end

    // The valid signal only triggers when it reaches the exact end of the register,
    // perfectly matching the latency of the t_chain math pipeline.
    assign valid_out = valid_shift[NUM_ROWS-1];

endmodule