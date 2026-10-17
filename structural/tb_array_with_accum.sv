`timescale 1ns / 1ps

module tb_array_with_accum();
    
    // ------------------------------------------
    // 1. PARAMETERS
    // ------------------------------------------
    parameter NUM_ROWS = 4;
    parameter NUM_COLS = 4;
    parameter DATA_WIDTH = 8;

    // ------------------------------------------
    // 2. SIGNALS
    // ------------------------------------------
    logic clk;
    logic rst;
    logic load_en;
    logic valid_in;
    logic [NUM_COLS-1:0] mask;
    logic accum_mode;

    // 2D Array Inputs
    logic [NUM_COLS-1:0][DATA_WIDTH-1:0] A_in_flat;
    logic [NUM_COLS-1:0][DATA_WIDTH-1:0] B_in_flat;

    // The Bridge Wires
    logic [NUM_ROWS-1:0] a_valid_vector_wire;
    logic [NUM_ROWS-1:0] row_match_wire;

    // Final Outputs
    logic final_t_i;
    logic final_valid;

    // ------------------------------------------
    // 3. DUT INSTANTIATIONS
    // ------------------------------------------
    
    pe_array_2d #(
        .NUM_ROWS(NUM_ROWS),
        .NUM_COLS(NUM_COLS),
        .DATA_WIDTH(DATA_WIDTH)
    ) DUT_ARRAY (
        .clk(clk),
        .rst(rst),
        .load_en(load_en),
        .valid_in(valid_in),
        .mask(mask),
        .A_in_flat(A_in_flat),
        .B_in_flat(B_in_flat),
        .a_valid_vector_out(a_valid_vector_wire),
        .row_match_out(row_match_wire)
    );

    accumulation_array #(
        .NUM_ROWS(NUM_ROWS)
    ) DUT_ACCUM (
        .clk(clk),
        .rst(rst),
        .row_match_out(row_match_wire),
        .valid_in(a_valid_vector_wire[0]), 
        .accum_mode(accum_mode),
        .t_i(final_t_i),
        .valid_out(final_valid)
    );

    // ------------------------------------------
    // 4. CLOCK GENERATION (100 MHz)
    // ------------------------------------------
    always #5 clk = ~clk;

    // ------------------------------------------
    // 5. EVENT-DRIVEN TASKS
    // ------------------------------------------
    task load_b_row(input logic [7:0] c3, c2, c1, c0);
        @(posedge clk);
        load_en <= 1'b1;  // Triggers exactly with the data
        B_in_flat[3] <= c3;
        B_in_flat[2] <= c2;
        B_in_flat[1] <= c1;
        B_in_flat[0] <= c0;
    endtask

    task stream_a_row(input logic [7:0] c3, c2, c1, c0);
        @(posedge clk);
        valid_in <= 1'b1; // Triggers exactly with the data
        A_in_flat[3] <= c3;
        A_in_flat[2] <= c2;
        A_in_flat[1] <= c1;
        A_in_flat[0] <= c0;
    endtask

    // ------------------------------------------
    // 6. MAIN TEST SEQUENCE
    // ------------------------------------------
    initial begin
        // --- STEP 1: INITIALIZE & RESET ---
        clk = 0;
        rst = 1;
        load_en = 0;
        valid_in = 0;
        mask = 4'b0000;
        accum_mode = 0;
        A_in_flat = '0;
        B_in_flat = '0;

        repeat(4) @(posedge clk); 
        rst <= 0;
        @(posedge clk);

        // --- STEP 2: LOAD PHASE (Table B) ---
        $display("--- Loading Table B ---");
        
        load_b_row(40, 255, 30, 10);
        load_b_row(99, 99, 99, 99);
        load_b_row(44, 255, 33, 11);
        load_b_row(0, 0, 0, 0);

        @(posedge clk);
        load_en <= 0;
        B_in_flat <= '0;
        
        repeat(2) @(posedge clk); 

        // --- STEP 3: EXECUTION PHASE (Intersection) ---
        $display("--- Executing Intersection on Column 2 (Mask 0100) ---");
        
        // Perfectly group the mode, mask, valid flag, and Row 0 data 
        // to fire on the exact same clock edge.
        @(posedge clk);
        accum_mode   <= 1'b0; 
        mask         <= 4'b1111; 
        valid_in     <= 1'b1;
        A_in_flat[3] <= 8'd40;
        A_in_flat[2] <= 8'd255;
        A_in_flat[1] <= 8'd30;
        A_in_flat[0] <= 8'd10;
        
        // Stream the remaining rows
        stream_a_row(4, 2, 3, 1);
        stream_a_row(99, 99, 99, 99);

        // --- STEP 4: FLUSH PHASE ---
        @(posedge clk);
        valid_in <= 0;
        A_in_flat <= '0;

        // --- STEP 5: EVENT-DRIVEN OUTPUT CHECK ---
        $display("Waiting for math to emerge from the pipeline...");
        wait(final_valid == 1'b1);
        $display("Data is flowing out!");
        
        wait(final_valid == 1'b0);
        $display("Pipeline is completely flushed.");

        #50; 
        $display("--- Testbench Complete ---");
        $finish;
    end
endmodule