`timescale 1ns / 1ps

module tb_pe_array_2d;

    // ==========================================
    // 1. HARDWARE PARAMETERS
    // ==========================================
    parameter NUM_ROWS   = 4;
    parameter NUM_COLS   = 4;
    parameter DATA_WIDTH = 8;

    // ==========================================
    // 2. MOTHERBOARD WIRES
    // ==========================================
    logic clk;
    logic rst;
    logic load_en;
    logic valid_in;
    logic [3:0] mask;

    // 2D Arrays for the data inputs (Little Endian: [0] is LSB on the right)
    logic [NUM_COLS-1:0][DATA_WIDTH-1:0] A_in;
    logic [NUM_COLS-1:0][DATA_WIDTH-1:0] B_in;

    // Outputs
    logic [NUM_ROWS-1:0] a_valid_vector_out;
    logic [NUM_ROWS-1:0] row_match_out;

    // ==========================================
    // 3. DUT INSTANTIATION
    // ==========================================
    pe_array_2d #(
        .NUM_ROWS(NUM_ROWS),
        .NUM_COLS(NUM_COLS),
        .DATA_WIDTH(DATA_WIDTH)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .load_en(load_en),
        .valid_in(valid_in),
        .mask(mask),
        
        // Ensure these port names match your pe_array_2d.sv exactly!
        .A_in_flat(A_in), 
        .B_in_flat(B_in),
        
        .a_valid_vector_out(a_valid_vector_out),
        .row_match_out(row_match_out)
    );

    // ==========================================
    // 4. CLOCK GENERATION (100 MHz)
    // ==========================================
    always #5 clk = ~clk;

    // Trap the match vector just like we did for the row!
    logic [NUM_ROWS-1:0] match_trap;
    always_ff @(posedge clk) begin
        if (rst) match_trap <= '0;
        else match_trap <= match_trap | (row_match_out & a_valid_vector_out);
    end

    // ==========================================
    // 5. THE SIMULATION SCRIPT
    // ==========================================
    initial begin
        // --- STEP A: Initialize and Reset ---
        clk = 0; rst = 1; load_en = 0; valid_in = 0; mask = 4'b0000;
        for (int i=0; i<NUM_COLS; i++) begin A_in[i] = 0; B_in[i] = 0; end
        
        #20; rst = 0; #20;

        // --- STEP B: The Bottom-Up Database Load ---
        $display("--- Loading Database into the Grid ---");
        // Because B_in enters at the bottom, we must push the top row's data in first, 
        // and let it float up to the ceiling.
        load_en = 1;
        
        // Push Row 0's Data (Ceiling) - Tuple: [10, 255, 30, 40]
        B_in[3] = 8'd10; B_in[2] = 8'd255; B_in[1] = 8'd30; B_in[0] = 8'd40; #10;
        
        // Push Row 1's Data - Tuple: [99, 99, 99, 99] (Garbage data)
        B_in[3] = 8'd99; B_in[2] = 8'd99; B_in[1] = 8'd99; B_in[0] = 8'd99; #10;
        
        // Push Row 2's Data - Tuple: [11, 255, 33, 44] (Another row with 255 in Col 2!)
        B_in[3] = 8'd11; B_in[2] = 8'd255; B_in[1] = 8'd33; B_in[0] = 8'd44; #10;
        
        // Push Row 3's Data (Floor) - Tuple: [0, 0, 0, 0]
        B_in[3] = 8'd0; B_in[2] = 8'd0; B_in[1] = 8'd0; B_in[0] = 8'd0; #10;

        load_en = 0; 
        for (int i=0; i<NUM_COLS; i++) B_in[i] = 0; // Clear the input bus
        #20;

        // --- STEP C: The Top-Down Query ---
        $display("--- Firing Query: Search for 255 in Column 2 ---");
        // We expect Row 0 and Row 2 to match!
        
        mask = 4'b0100; // Target Column 2
        
        // Load the flat query into A_in. The internal stagger_module will handle the delay!
        A_in[3] = 8'd0; 
        A_in[2] = 8'd255; // The Target
        A_in[1] = 8'd0; 
        A_in[0] = 8'd0;
        
        valid_in = 1; // Pull the trigger
        #10;
        
        valid_in = 0; // Release the trigger
        for (int i=0; i<NUM_COLS; i++) A_in[i] = 0;

        // --- STEP D: Wait for the result to fall out the bottom ---
        // We wait dynamically for the valid bit to drop out of the very bottom row (Row 3).
        fork
            begin
                wait(a_valid_vector_out[3] == 1'b1);
            end
            begin
                #200; // Failsafe timeout
                $display("CRITICAL ERROR: Data never reached the bottom of the array.");
            end
        join_any
        disable fork;
        
        // Give it a couple extra cycles for the horizontal match of the bottom row to pop out
        #20; 

        // --- STEP E: Evaluate the Trap ---
        $display("Final Captured Match Vector: %b", match_trap);
        
        // We expect Row 0 (bit 0) and Row 2 (bit 2) to be 1. 
        // Binary: 0101 (which is 5 in decimal).
        if (match_trap == 4'b0101) begin
            $display("PASS: Multi-Row Systolic Execution Successful!");
        end else begin
            $display("FAIL: Expected 0101, but got %b", match_trap);
        end

        #50;
        $display("Hardware Execution Complete!");
        $stop;
    end

endmodule