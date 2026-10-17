`timescale 1ns / 1ps

module tb_top_PE;

    // ==========================================
    // 1. HARDWARE PARAMETERS
    // ==========================================
    parameter DATA_WIDTH = 8;

    // ==========================================
    // 2. MOTHERBOARD WIRES
    // ==========================================
    logic clk;
    logic rst;
    logic load_en;
    logic match_in;    // Cascades from the previous PE in the row
    logic mask;        // 1-bit mask (1 = check data, 0 = ignore and pass match_in)
    logic a_valid_in;

    logic [DATA_WIDTH-1:0] a_in;
    logic [DATA_WIDTH-1:0] b_in;

    // Outputs
    logic [DATA_WIDTH-1:0] a_out;
    logic [DATA_WIDTH-1:0] b_pass;
    logic match_out;
    logic a_valid_out;

    // ==========================================
    // 3. DUT INSTANTIATION
    // ==========================================
    top_PE #(
        .DATA_WIDTH(DATA_WIDTH)
    ) DUT (
        .clk         (clk),
        .rst         (rst),
        .load_en     (load_en),
        .match_in    (match_in),
        .mask        (mask),
        .a_valid_in  (a_valid_in),
        .a_in        (a_in),
        .b_in        (b_in),
        
        .a_out       (a_out),
        .b_pass      (b_pass),
        .match_out   (match_out),
        .a_valid_out (a_valid_out)
    );

    // ==========================================
    // 4. CLOCK GENERATION (100 MHz)
    // ==========================================
    always #5 clk = ~clk;

    // ==========================================
    // 5. THE SIMULATION SCRIPT
    // ==========================================
    initial begin
        // --- STEP A: Initialize and Reset ---
        clk = 0;
        rst = 1;
        load_en = 0;
        match_in = 1; // Default to 1 (Assume the previous PE matched)
        mask = 0;
        a_valid_in = 0;
        a_in = 8'h00;
        b_in = 8'h00;
        
        #20;
        rst = 0;
        #20;

        // --- STEP B: Flash the Database Byte (B) ---
        // Load the value 8'd255 into the B register.
        b_in = 8'd255;
        load_en = 1;
        #10;
        load_en = 0;
        b_in = 8'd0; // Clear the wire, the BREG should hold the data
        #10;

        // --- STEP C: Test 1 - Perfect Match ---
        $display("--- Test 1: Perfect Match ---");
        // We want to check this column (mask=1), previous column matched (match_in=1)
        mask = 1;
        match_in = 1;
        a_in = 8'd255; 
        a_valid_in = 1;
        
        #10; // Cycle 1: Data clocks into `areg`
        a_valid_in = 0;
        a_in = 8'd0;
        
        #10; // Cycle 2: Combinational math finishes, clocks into `match_out_reg`
        if (match_out == 1'b1) $display("PASS: Perfect Match"); 
        else $display("FAIL: Perfect Match");
        #20;

        // --- STEP D: Test 2 - Mismatch ---
        $display("--- Test 2: Mismatch ---");
        mask = 1;
        match_in = 1;
        a_in = 8'd100; // Sending 100, expecting 255
        a_valid_in = 1;
        
        #10; // Cycle 1
        a_valid_in = 0;
        a_in = 8'd0;
        
        #10; // Cycle 2
        if (match_out == 1'b0) $display("PASS: Mismatch caught"); 
        else $display("FAIL: Mismatch missed");
        #20;

        // --- STEP E: Test 3 - The Mask Bypass ---
        $display("--- Test 3: Mask Bypass ---");
        // The data is totally wrong (100 vs 255), BUT mask is 0.
        // The MUX should route `match_in` directly to `match_out`, ignoring the comparator.
        mask = 0;
        match_in = 1;
        a_in = 8'd100; 
        a_valid_in = 1;
        
        #10; // Cycle 1
        a_valid_in = 0;
        a_in = 8'd0;
        
        #10; // Cycle 2
        if (match_out == 1'b1) $display("PASS: Mask successfully bypassed bad data"); 
        else $display("FAIL: Mask failed to bypass");
        #20;

        // --- STEP F: Test 4 - Cascaded Failure ---
        $display("--- Test 4: Cascaded Failure ---");
        // Data is perfectly correct (255 vs 255) and mask is active.
        // BUT the previous column failed (match_in = 0).
        // The AND gate should force this PE to also output 0.
        mask = 1;
        match_in = 0; 
        a_in = 8'd255; 
        a_valid_in = 1;
        
        #10; // Cycle 1
        a_valid_in = 0;
        a_in = 8'd0;
        
        #10; // Cycle 2
        if (match_out == 1'b0) $display("PASS: Cascaded failure respected"); 
        else $display("FAIL: Cascaded failure ignored");

        #50;
        $display("Hardware Execution Complete!");
        $stop;
    end

endmodule