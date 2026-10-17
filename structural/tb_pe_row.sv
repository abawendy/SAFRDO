`timescale 1ns / 1ps

module tb_pe_row;

    // ==========================================
    // 1. HARDWARE PARAMETERS
    // ==========================================
    parameter DATA_WIDTH = 8;

    // ==========================================
    // 2. MOTHERBOARD WIRES
    // ==========================================
    logic clk, rst, load_en;
    
    logic a_valid_in_0, a_valid_in_1, a_valid_in_2, a_valid_in_3;
    logic a_valid_out_0, a_valid_out_1, a_valid_out_2, a_valid_out_3;
    
    logic [3:0] mask;

    logic [DATA_WIDTH-1:0] a_in_0, a_in_1, a_in_2, a_in_3;
    logic [DATA_WIDTH-1:0] b_in_0, b_in_1, b_in_2, b_in_3;
    
    logic [DATA_WIDTH-1:0] a_out_0, a_out_1, a_out_2, a_out_3;
    logic [DATA_WIDTH-1:0] b_pass_0, b_pass_1, b_pass_2, b_pass_3;
    
    logic row_match_out;

    // ==========================================
    // 3. DUT INSTANTIATION
    // ==========================================
    pe_row #(.DATA_WIDTH(DATA_WIDTH)) DUT (.*); // Wildcard connection since names match exactly

    // ==========================================
    // 4. CLOCK GENERATION (100 MHz)
    // ==========================================
    always #5 clk = ~clk;

    // ==========================================
    // 5. THE SIMULATION SCRIPT
    // ==========================================
    initial begin
        // --- STEP A: Initialize and Reset ---
        clk = 0; rst = 1; load_en = 0; mask = 4'b0000;
        a_valid_in_0 = 0; a_valid_in_1 = 0; a_valid_in_2 = 0; a_valid_in_3 = 0;
        a_in_0 = 0; a_in_1 = 0; a_in_2 = 0; a_in_3 = 0;
        b_in_0 = 0; b_in_1 = 0; b_in_2 = 0; b_in_3 = 0;
        
        #20;
        rst = 0;
        #20;

        // --- STEP B: Flash the Database Tuple (LITTLE ENDIAN) ---
        // Tuple: [10, 255, 30, 40]
        // Col 0 is the right-most byte (LSB)
        b_in_3 = 8'd10;  // MSB
        b_in_2 = 8'd255; // Target
        b_in_1 = 8'd30;
        b_in_0 = 8'd40;  // LSB
        
        load_en = 1; #10; load_en = 0;
        
        // Clear B inputs to prove the row saved the data
        b_in_3 = 0; b_in_2 = 0; b_in_1 = 0; b_in_0 = 0;
        #20;

        // --- STEP C: Test 1 - The Staggered Perfect Match ---
        $display("--- Test 1: Staggered Match (Target: 255 in Col 2) ---");
        mask = 4'b0100; // Check Column 2
        
        // Cycle 1: Col 0
        a_in_0 = 8'd0; a_valid_in_0 = 1; #10; a_in_0 = 0; a_valid_in_0 = 0;
        
        // Cycle 2: Col 1
        a_in_1 = 8'd0; a_valid_in_1 = 1; #10; a_in_1 = 0; a_valid_in_1 = 0;
        
        // Cycle 3: Col 2 (THE TARGET)
        a_in_2 = 8'd255; a_valid_in_2 = 1; #10; a_in_2 = 0; a_valid_in_2 = 0;
        
        // Cycle 4: Col 3
        a_in_3 = 8'd0; a_valid_in_3 = 1; #10; a_in_3 = 0; a_valid_in_3 = 0;
        
        // EVENT-DRIVEN WAIT: Wait dynamically for the match to go high!
        // We use fork/join_any to add a timeout just in case the logic is broken.
        fork
            begin
                wait(row_match_out == 1'b1);
                $display("PASS: Row Match Success (Dynamic Catch!)");
            end
            begin
                #100; // Timeout failsafe
                $display("FAIL: Row Match timed out.");
            end
        join_any
        disable fork; // Kill the timeout if the match succeeded
        
        #20;

        // --- STEP D: Test 2 - The Cascaded Failure ---
        $display("--- Test 2: Full Tuple Mismatch ---");
        
        mask = 4'b1111; // Check ALL columns
        
        // Sending [10, 255, 30, 99] (Col 0 fails)
        a_in_0 = 8'd99;  a_valid_in_0 = 1; #10; a_in_0 = 0; a_valid_in_0 = 0; // BAD DATA
        a_in_1 = 8'd30;  a_valid_in_1 = 1; #10; a_in_1 = 0; a_valid_in_1 = 0;
        a_in_2 = 8'd255; a_valid_in_2 = 1; #10; a_in_2 = 0; a_valid_in_2 = 0;
        a_in_3 = 8'd10;  a_valid_in_3 = 1; #10; a_in_3 = 0; a_valid_in_3 = 0;
        
        // EVENT-DRIVEN WAIT: We expect a failure, so row_match_out won't go high.
        // Instead, we wait for a_valid_out_3 to go high, which tells us Col 3 is finished.
        wait(a_valid_out_3 == 1'b1);
        
        // Wait 2 extra cycles for the horizontal math to finish popping out of Col 3
        #20; 
        
        if (row_match_out == 1'b0) $display("PASS: One bad column vetoed the row");
        else $display("FAIL: Row incorrectly matched");

        #20;
        $display("Hardware Execution Complete!");
        $stop;
    end

endmodule