`timescale 1ns / 1ps

module safrdo_bram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10  // 10 bits = 1024 rows of depth
)(
    input  logic                  clk,

    // ==========================================
    // PORT A: Host CPU Side (For Loading)
    // ==========================================
    input  logic                  we,      // Write Enable
    input  logic [ADDR_WIDTH-1:0] addr_in, // Write Address
    input  logic [DATA_WIDTH-1:0] data_in, // Data from Laptop/CPU
    
    // ==========================================
    // PORT B: Controller/Datapath Side (For Execution)
    // ==========================================
    input  logic [ADDR_WIDTH-1:0] addr_out, // Read Address from Controller
    output logic [DATA_WIDTH-1:0] data_out  // 32-bit row strictly to Datapath
);

    // ==========================================
    // 1. THE PHYSICAL MEMORY ARRAY
    // ==========================================
    // Defines a memory block 32 bits wide and 1024 rows deep
    logic [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    // ==========================================
    // 2. HARDWARE INITIALIZATION (The "Bake It In" Method)
    // ==========================================
    // This block runs once during bitstream generation in Vivado.
    // It pre-loads the memory with your database so it is ready on power-up.
    // initial begin
    //     // Ensure "table_data.txt" is added to your Vivado project 
    //     // as a "Simulation Source" AND a "Design Source".
    //     $readmemh("table_data.txt", ram);
    // end

    // ==========================================
    // 3. SYNCHRONOUS READ / WRITE LOGIC
    // ==========================================
    // Artix-7 requires BRAMs to be strictly synchronous (clocked).
    always_ff @(posedge clk) begin
        // Port A: Write logic
        if (we) begin
            ram[addr_in] <= data_in;
        end
        
        // Port B: Read logic
        // Takes exactly 1 clock cycle for the data to emerge after the address changes
        data_out <= ram[addr_out]; 
    end

endmodule