`timescale 1ns / 1ps

module tb_safrdo_top;

    // ==========================================
    // 1. HARDWARE PARAMETERS
    // ==========================================
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 10;
    parameter NUM_ROWS   = 100;   // SCALED smoke test (loads 4 rows, matches at row 2)

    // ==========================================
    // 2. MOTHERBOARD WIRES
    // ==========================================
    logic clk;
    logic rst;
    logic cpu_start;
    logic done_signal;

    // Direct Instruction Input (Replaces IMEM)
    logic [15:0]           cpu_instruction;

    logic                  cpu_we_A;
    logic [ADDR_WIDTH-1:0] cpu_addr_A;
    logic [DATA_WIDTH-1:0] cpu_data_A;

    logic                  cpu_we_B;
    logic [ADDR_WIDTH-1:0] cpu_addr_B;
    logic [DATA_WIDTH-1:0] cpu_data_B;

    logic [NUM_ROWS-1:0]   final_data_out;
    logic [NUM_ROWS-1:0]   final_valid_out;

    // Real loaded row counts (bridge normally supplies these from its load pointers)
    logic [9:0]            num_a_rows;
    logic [9:0]            num_b_rows;

    // Join collector read address. The bridge drives this in the real system;
    // here the testbench plays the bridge and walks the B-rows during read-out.
    localparam int IDX_W = $clog2(NUM_ROWS);
    logic [IDX_W-1:0]      join_row_sel;

    // ==========================================
    // 3. DUT INSTANTIATION
    // ==========================================
    safrdo_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .NUM_ROWS(NUM_ROWS)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .cpu_start(cpu_start),
        .done_signal(done_signal),

        .cpu_instruction(cpu_instruction), // Direct connection
        .num_a_rows(num_a_rows),
        .num_b_rows(num_b_rows),
        .join_row_sel(join_row_sel),

        .cpu_we_A(cpu_we_A),       .cpu_addr_A(cpu_addr_A),       .cpu_data_A(cpu_data_A),
        .cpu_we_B(cpu_we_B),       .cpu_addr_B(cpu_addr_B),       .cpu_data_B(cpu_data_B),

        .final_data_out(final_data_out),
        .final_valid_out(final_valid_out)
    );

    // ==========================================
    // 4. CLOCK GENERATION (100 MHz)
    // ==========================================
    always #5 clk = ~clk;

    logic [NUM_ROWS-1:0] result_reg;

        always @(posedge clk) begin
            if (rst) result_reg <= '0;
            else     result_reg <= result_reg | (final_data_out & final_valid_out);
        end

    // ==========================================
    // 5. THE SIMULATION SCRIPT
    // ==========================================
    initial begin
        // --- STEP A: Power On & Clear Memory ---
        clk = 0; rst = 1; cpu_start = 0;
        
        // IMEM clear removed
        cpu_instruction = 16'h0000; 

        cpu_we_A = 0; cpu_addr_A = 0; cpu_data_A = 0;
        cpu_we_B = 0; cpu_addr_B = 0; cpu_data_B = 0;
        num_a_rows = 0; num_b_rows = 0; join_row_sel = 0;
        #20;
        rst = 0; 
        #20;

        // --- STEP B: Flash the Database into BRAM B ---
        // Selection Query: BRAM B holds the 4 database tuples. 
        // We are going to search for the value 255 in Column 2.
        cpu_we_B = 1;

        // Tuple 0 in BRAM B (Col 2 is 255 -> SHOULD MATCH)
        cpu_addr_B = 0; 
        cpu_data_B[31:24] = 8'd10;  // Column 3
        cpu_data_B[23:16] = 8'd20; // Column 2 (Target)
        cpu_data_B[15:8]  = 8'd30;  // Column 1
        cpu_data_B[7:0]   = 8'd40;  // Column 0
        #10;

        // Tuple 1 in BRAM B (Col 2 is 100 -> SHOULD FAIL)
        cpu_addr_B = 1; 
        cpu_data_B[31:24] = 8'd11; 
        cpu_data_B[23:16] = 8'd100; 
        cpu_data_B[15:8]  = 8'd11; 
        cpu_data_B[7:0]   = 8'd11; 
        #10;

        // Tuple 2 in BRAM B (Col 2 is 255 -> SHOULD MATCH)
        cpu_addr_B = 2; 
        cpu_data_B[31:24] = 8'd99; 
        cpu_data_B[23:16] = 8'd255; // Column 2 (Target)
        cpu_data_B[15:8]  = 8'd77; 
        cpu_data_B[7:0]   = 8'd66; 
        #10;

        // Tuple 3 in BRAM B (Col 2 is 5 -> SHOULD FAIL)
        cpu_addr_B = 3; 
        cpu_data_B[31:24] = 8'd5; 
        cpu_data_B[23:16] = 8'd5; 
        cpu_data_B[15:8]  = 8'd5; 
        cpu_data_B[7:0]   = 8'd5; 
        #10;
        
        cpu_we_B = 0; 
        
        // Note: BRAM A remains completely empty.


        // --- STEP C: Set the Hardcoded Instruction ---
        // Instruction: Selection (Opcode: 00)
        // Mask: Target Column 2 (Mask: 0100)
        // Immediate Target: 255 (8'hFF)
        // Binary Layout: [15:8 Immediate] [7 EOP] [6 Unused] [5:2 Mask] [1:0 Opcode]
        // Binary: 11111111_0_0_0100_00  -> Hex: 16'hFF10
        
        cpu_instruction = 16'hFF10; 
        #10;

        // --- STEP D: Press the Start Button ---
        #20;
        cpu_start = 1;
        #10;
        cpu_start = 0;

        // --- STEP E: Wait for Hardware to Finish ---
        // Ensure the pipeline drains completely
        wait(done_signal == 1'b1);
        #650; // Delay for 65 clock cycles

        $display("Result: %b (expected 4'b0100)", result_reg);

        $display("Hardware Execution Complete!");
        $display("Check final_data_out in Vivado. It should equal 4'b0101.");
        $stop; 
    end

endmodule