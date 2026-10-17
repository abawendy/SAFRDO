// `timescale 1ns / 1ps

// module safrdo_top #(
//     parameter DATA_WIDTH = 32,
//     parameter NUM_COLS   = 4,
//     parameter ADDR_WIDTH = 10,
//     parameter NUM_ROWS   = 50
// )(
//     input  logic clk,
//     input  logic rst,

//     // ==========================================
//     // HOST INTERFACE (From Laptop CPU)
//     // ==========================================
//     input  logic                  cpu_start,   // Wakes up the FSM
//     output logic                  done_signal, // Tells laptop we are finished

//     // IMEM Loading Ports (16-bit)
//     input  logic                  cpu_we_imem,
//     input  logic [ADDR_WIDTH-1:0] cpu_addr_imem,
//     input  logic [15:0]           cpu_data_imem,

//     // DMEM A Loading Ports (32-bit)
//     input  logic                  cpu_we_A,
//     input  logic [ADDR_WIDTH-1:0] cpu_addr_A,
//     input  logic [DATA_WIDTH-1:0] cpu_data_A,

//     // DMEM B Loading Ports (32-bit)
//     input  logic                  cpu_we_B,
//     input  logic [ADDR_WIDTH-1:0] cpu_addr_B,
//     input  logic [DATA_WIDTH-1:0] cpu_data_B,

//     // Final Output Readout
//     output logic [NUM_ROWS-1:0]   final_data_out,
//     output logic [NUM_ROWS-1:0]   final_valid_out
// );

//     // ==========================================
//     // INTERNAL WIRES (The Motherboard Traces)
//     // ==========================================
//     // Instruction Bus
//     logic [9:0]  pc_addr_wire;
//     logic [15:0] instruction_wire;
//     logic [15:0] safe_instruction_wire;

//     // Address Buses
//     logic [9:0]  addr_a_wire;
//     logic [9:0]  addr_b_wire;

//     // Data Buses
//     logic [31:0] data_a_wire;
//     logic [31:0] data_b_wire;

//     // Control Signals
//     logic        valid_wire;
//     logic        load_en_wire;
//     logic        sel_data_A_wire;
//     logic        out_sel_wire;
//     logic        accum_mode_wire;

//     // Sliced Instruction Wires for the Datapath
//     logic [1:0]  opcode_wire;
//     logic [3:0]  mask_wire;
//     logic [7:0]  imm_wire;

//     // Extracting the ISA fields directly off the bus for the Datapath
//     assign imm_wire    = safe_instruction_wire[15:8];
//     assign mask_wire   = safe_instruction_wire[5:2];
//     assign opcode_wire = safe_instruction_wire[1:0];


//     // ==========================================
//     // 1. THE BRAIN (FSM Controller)
//     // ==========================================
//     safrdo_controller #(
//         .TABLE_A_DEPTH(NUM_ROWS),
//         .TABLE_B_DEPTH(NUM_ROWS + 1) // Adjust this based on how many PEs are in a column
//     ) U_Controller (
//         .clk            (clk),
//         .rst            (rst),
//         .cpu_start      (cpu_start),
//         .instruction_in (instruction_wire),
        
//         .imem_addr_out  (pc_addr_wire),
//         .bram_addr_A    (addr_a_wire),
//         .bram_addr_B    (addr_b_wire),
        
//         .valid_in       (valid_wire),
//         .load_en        (load_en_wire),
//         .sel_data_A     (sel_data_A_wire),
//         .out_sel        (out_sel_wire),
//         .done_signal    (done_signal),
//         .locked_instruction_out(safe_instruction_wire),
//         .accum_mode     (accum_mode_wire)
//     );

//     // ==========================================
//     // 2. INSTRUCTION MEMORY (16-bit IMEM)
//     // ==========================================
//     safrdo_bram #(
//         .DATA_WIDTH(16),
//         .ADDR_WIDTH(ADDR_WIDTH)
//     ) U_IMEM (
//         .clk      (clk),
//         .we       (cpu_we_imem),
//         .addr_in  (cpu_addr_imem),
//         .data_in  (cpu_data_imem),
//         .addr_out (pc_addr_wire),      // Driven by Controller PC
//         .data_out (instruction_wire)   // Feeds Controller & Datapath
//     );

//     // ==========================================
//     // 3. TABLE A MEMORY (32-bit DMEM)
//     // ==========================================
//     safrdo_bram #(
//         .DATA_WIDTH(DATA_WIDTH),
//         .ADDR_WIDTH(ADDR_WIDTH)
//     ) U_BRAM_A (
//         .clk      (clk),
//         .we       (cpu_we_A),
//         .addr_in  (cpu_addr_A),
//         .data_in  (cpu_data_A),
//         .addr_out (addr_a_wire), // Driven by Controller A_counter
//         .data_out (data_a_wire)  // Feeds into Datapath input
//     );

//     // ==========================================
//     // 4. TABLE B MEMORY (32-bit DMEM)
//     // ==========================================
//     safrdo_bram #(
//         .DATA_WIDTH(DATA_WIDTH),
//         .ADDR_WIDTH(ADDR_WIDTH)
//     ) U_BRAM_B (
//         .clk      (clk),
//         .we       (cpu_we_B),
//         .addr_in  (cpu_addr_B),
//         .data_in  (cpu_data_B),
//         .addr_out (addr_b_wire), // Driven by Controller B_counter
//         .data_out (data_b_wire)  // Feeds into Datapath input
//     );

//     // ==========================================
//     // 5. THE BRAWN (Datapath Math Core)
//     // ==========================================
//     safrdo_datapath #(
//         .NUM_ROWS(NUM_ROWS),
//         .NUM_COLS(NUM_COLS),
//         .DATA_WIDTH(32)
//     ) U_Datapath (
//         .clk               (clk),
//         .rst               (rst),
        
//         // Memory Sockets
//         .bram_table_a_data (data_a_wire),
//         .bram_table_b_data (data_b_wire),
        
//         // Sliced Instruction Sockets
//         .opcode_in         (safe_instruction_wire[1:0]),
//         .mask_in           (safe_instruction_wire[5:2]),
//         .imm_in            (safe_instruction_wire[15:8]),
        
//         // Control Lever Sockets
//         .sel_data_A        (sel_data_A_wire),
//         .load_en           (load_en_wire),
//         .array_valid_in    (valid_wire),
//         .out_sel           (out_sel_wire),
//         .accum_mode        (accum_mode_wire),
        
//         // Output to Host
//         .final_data_out    (final_data_out),
//         .final_valid_out   (final_valid_out)
//     );

// endmodule





`timescale 1ns / 1ps

module safrdo_top #(
    parameter DATA_WIDTH = 32,
    parameter NUM_COLS   = 4,
    parameter ADDR_WIDTH = 10,
    parameter NUM_ROWS   = 50
)(
    input  logic clk,
    input  logic rst,

    // ==========================================
    // HOST INTERFACE (From Laptop CPU)
    // ==========================================
    input  logic                  cpu_start,   // Wakes up the FSM
    output logic                  done_signal, // Tells laptop we are finished

    // DIRECT INSTRUCTION (Replaces IMEM)
    input  logic [15:0]           cpu_instruction,

    // Real loaded row counts (from the bridge load pointers) -- bounds JOIN
    input  logic [9:0]            num_a_rows,
    input  logic [9:0]            num_b_rows,

    // Join collector read address (bridge walks the B-rows during read-out)
    input  logic [$clog2(NUM_ROWS)-1:0] join_row_sel,

    // DMEM A Loading Ports (32-bit)
    input  logic                  cpu_we_A,
    input  logic [ADDR_WIDTH-1:0] cpu_addr_A,
    input  logic [DATA_WIDTH-1:0] cpu_data_A,

    // DMEM B Loading Ports (32-bit)
    input  logic                  cpu_we_B,
    input  logic [ADDR_WIDTH-1:0] cpu_addr_B,
    input  logic [DATA_WIDTH-1:0] cpu_data_B,

    // Final Output Readout
    output logic [NUM_ROWS-1:0]   final_data_out,
    output logic [NUM_ROWS-1:0]   final_valid_out
);

    // ==========================================
    // INTERNAL WIRES (The Motherboard Traces)
    // ==========================================
    logic [15:0] safe_instruction_wire; // The locked instruction from the FSM

    // Address Buses
    logic [9:0]  addr_a_wire;
    logic [9:0]  addr_b_wire;

    // Data Buses
    logic [31:0] data_a_wire;
    logic [31:0] data_b_wire;

    // Control Signals
    logic        valid_wire;
    logic        load_en_wire;
    logic        sel_data_A_wire;
    logic [1:0]  out_sel_wire;         // widened: 00 Vector, 01 Scalar, 10 Join
    logic        accum_mode_wire;

    // Join collector control
    localparam int IDX_W = $clog2(NUM_ROWS);
    logic              join_clear_wire;   // controller -> collector (matrix wipe)

    // ==========================================
    // 1. THE BRAIN (Single-Instruction FSM Controller)
    // ==========================================
    safrdo_controller #(
        .TABLE_A_DEPTH(NUM_ROWS),
        .TABLE_B_DEPTH(NUM_ROWS + 1), // Kept your parameter adjustment
        .NUM_ROWS     (NUM_ROWS)
    ) U_Controller (
        .clk            (clk),
        .rst            (rst),
        .cpu_start      (cpu_start),
        .instruction_in (cpu_instruction), // Wires directly from the host pin
        .num_a_rows     (num_a_rows),
        .num_b_rows     (num_b_rows),

        .bram_addr_A    (addr_a_wire),
        .bram_addr_B    (addr_b_wire),

        .valid_in       (valid_wire),
        .load_en        (load_en_wire),
        .sel_data_A     (sel_data_A_wire),
        .out_sel        (out_sel_wire),
        .done_signal    (done_signal),

        // Join collector control (matrix wipe only; read-out is bridge-paced)
        .join_clear     (join_clear_wire),

        .locked_instruction_out(safe_instruction_wire),
        .accum_mode     (accum_mode_wire)
    );

    // ==========================================
    // 2. INSTRUCTION MEMORY (REMOVED)
    // ==========================================
    // U_IMEM has been ripped out to test the datapath directly.

    // ==========================================
    // 3. TABLE A MEMORY (32-bit DMEM)
    // ==========================================
    safrdo_bram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) U_BRAM_A (
        .clk      (clk),
        .we       (cpu_we_A),
        .addr_in  (cpu_addr_A),
        .data_in  (cpu_data_A),
        .addr_out (addr_a_wire), // Driven by Controller A_counter
        .data_out (data_a_wire)  // Feeds into Datapath input
    );

    // ==========================================
    // 4. TABLE B MEMORY (32-bit DMEM)
    // ==========================================
    safrdo_bram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) U_BRAM_B (
        .clk      (clk),
        .we       (cpu_we_B),
        .addr_in  (cpu_addr_B),
        .data_in  (cpu_data_B),
        .addr_out (addr_b_wire), // Driven by Controller B_counter
        .data_out (data_b_wire)  // Feeds into Datapath input
    );

    // ==========================================
    // 5. THE BRAWN (Datapath Math Core)
    // ==========================================
    safrdo_datapath #(
        .NUM_ROWS(NUM_ROWS),
        .NUM_COLS(NUM_COLS),
        .DATA_WIDTH(32)
    ) U_Datapath (
        .clk               (clk),
        .rst               (rst),
        
        // Memory Sockets
        .bram_table_a_data (data_a_wire),
        .bram_table_b_data (data_b_wire),
        
        // Sliced Instruction Sockets (Pulls from the safely locked FSM register)
        .opcode_in         (safe_instruction_wire[1:0]),
        .mask_in           (safe_instruction_wire[5:2]),
        .imm_in            (safe_instruction_wire[15:8]),
        
        // Control Lever Sockets
        .sel_data_A        (sel_data_A_wire),
        .load_en           (load_en_wire),
        .array_valid_in    (valid_wire),
        .out_sel           (out_sel_wire),
        .accum_mode        (accum_mode_wire),

        // Join collector control
        .join_clear        (join_clear_wire),
        .join_row_sel      (join_row_sel),   // bridge-driven read address

        // Output to Host
        .final_data_out    (final_data_out),
        .final_valid_out   (final_valid_out)
    );

endmodule