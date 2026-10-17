`timescale 1ns / 1ps

module tb_stagger_module;

    // ==========================================
    // 1. HARDWARE PARAMETERS
    // ==========================================
    parameter DATA_WIDTH = 8;
    parameter NUM_COLS   = 4;

    // ==========================================
    // 2. MOTHERBOARD WIRES
    // ==========================================
    logic clk;
    logic reset;
    
    // Inputs
    logic [NUM_COLS-1:0][DATA_WIDTH-1:0] A_in;
    logic valid_in;

    // Outputs
    logic [NUM_COLS-1:0][DATA_WIDTH-1:0] A_out;
    logic [NUM_COLS-1:0] a_valid;

    // ==========================================
    // 3. DUT INSTANTIATION
    // ==========================================
    stagger_module #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_COLS(NUM_COLS)
    ) DUT (
        .clk(clk),
        .reset(reset),
        .A_in(A_in),
        .valid_in(valid_in),
        .A_out(A_out),
        .a_valid(a_valid)
    );

    // ==========================================
    // 4. CLOCK GENERATION (100 MHz)
    // ==========================================
    always #5 clk = ~clk;

    // Helper block to print what pops out of the module on every clock cycle
    always_ff @(posedge clk) begin
        if (!reset && a_valid != 0) begin
            $display("Time: %0t | Valid Vector: %b | Data Out: [Col3:%0d] [Col2:%0d] [Col1:%0d] [Col0:%0d]", 
                     $time, a_valid, A_out[3], A_out[2], A_out[1], A_out[0]);
        end
    end

    // ==========================================
    // 5. THE SIMULATION SCRIPT
    // ==========================================
    initial begin
        // --- STEP A: Initialize and Reset ---
        clk = 0;
        reset = 1;
        valid_in = 0;
        for (int i = 0; i < NUM_COLS; i++) A_in[i] = 8'd0;
        
        #20;
        reset = 0;
        #20;

        // --- STEP B: Test 1 - The Single Pulse ---
        $display("--- Test 1: Single Tuple Pulse ---");
        // We push exactly one tuple into the pipeline and watch it spread out.
        // Little Endian: Col 0 = rightmost, Col 3 = leftmost
        A_in[3] = 8'd40;
        A_in[2] = 8'd30;
        A_in[1] = 8'd20;
        A_in[0] = 8'd10;
        valid_in = 1;
        
        #10; // Wait 1 Clock Cycle
        
        // Immediately drop the inputs back to 0. 
        // The data is now trapped inside the shift registers!
        valid_in = 0;
        for (int i = 0; i < NUM_COLS; i++) A_in[i] = 8'd0;

        // Wait dynamically for the final column (Col 3) to pop out its valid bit
        wait(a_valid[3] == 1'b1);
        
        // Wait one extra cycle to let the data clear the pipes completely
        #10; 
        $display("Test 1 Complete: Single tuple successfully staggered.\n");
        #20;


        // --- STEP C: Test 2 - The Continuous Stream ---
        $display("--- Test 2: Continuous Pipelined Stream ---");
        // Real database queries stream continuously. We will fire 3 tuples back-to-back 
        // to prove the shift registers don't overwrite each other.
        
        // Cycle 1: Tuple A
        A_in[3] = 8'd44; A_in[2] = 8'd33; A_in[1] = 8'd22; A_in[0] = 8'd11; valid_in = 1;
        #10;
        
        // Cycle 2: Tuple B
        A_in[3] = 8'd88; A_in[2] = 8'd77; A_in[1] = 8'd66; A_in[0] = 8'd55; valid_in = 1;
        #10;
        
        // Cycle 3: Tuple C
        A_in[3] = 8'd12; A_in[2] = 8'd10; A_in[1] = 8'd99; A_in[0] = 8'd15; valid_in = 1;
        #10;
        
        // Cut the stream
        valid_in = 0;
        for (int i = 0; i < NUM_COLS; i++) A_in[i] = 8'd0;

        // Wait dynamically for the very last valid bit of Tuple C to exit Col 3
        // Because we sent 3 tuples, we wait for a_valid[3] to drop back to 0.
        wait(a_valid[3] == 1'b1); // Wait for Tuple A to hit the end
        wait(a_valid[3] == 1'b0); // Wait for the rest of the stream to finish and go quiet
        
        #10;
        $display("Test 2 Complete: Pipeline fully flushed.");
        
        #20;
        $display("Hardware Execution Complete!");
        $stop;
    end

endmodule