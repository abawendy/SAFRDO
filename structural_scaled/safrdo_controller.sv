// `timescale 1ns / 1ps

// module safrdo_controller #(
//     parameter TABLE_A_DEPTH = 50,
//     parameter TABLE_B_DEPTH = 4
// )(
//     input  logic        clk, rst, cpu_start,
//     input  logic [15:0] instruction_in,
    
//     output logic [9:0]  imem_addr_out, bram_addr_A, bram_addr_B,
//     output logic        valid_in, load_en, sel_data_A, out_sel, done_signal, accum_mode,
//     output logic [15:0] locked_instruction_out
    
    
// );

//     typedef enum logic [2:0] {IDLE, PREFETCH, FETCH, DECODE, LOAD_B, STREAM_A, FLUSH, NEXT} state_t;
//     state_t ps, ns;

//     // ------------------------------------------
//     // INTERNAL DATAPATH (The Counters & Registers)
//     // ------------------------------------------
//     logic [9:0]  pc_reg, A_counter, B_counter, flush_counter;
//     logic [15:0] IR;

//     // Decoded Instruction Wires
//     logic [7:0] dec_imm; 
//     logic       dec_eop; 
//     logic [3:0] dec_mask; 
//     logic [1:0] dec_opcode;

//     assign dec_imm    = IR[15:8];
//     assign dec_eop    = IR[7];
//     assign dec_mask   = IR[5:2];
//     assign dec_opcode = IR[1:0];


//     // ==========================================
//     // BLOCK 1: STATE REGISTER
//     // ==========================================
//     always_ff @(posedge clk) begin : state_reg_block
//         if (rst) 
//             ps <= IDLE;
//         else     
//             ps <= ns;
//     end

//     // ==========================================
//     // BLOCK 2: NEXT STATE LOGIC
//     // ==========================================
//     always_comb begin : ns_logic
//         case(ps)
//             IDLE : begin
//                 if (cpu_start) ns = FETCH;
//                 else           ns = IDLE;
//             end
            
//             FETCH : ns = DECODE;
            
//             DECODE : ns = LOAD_B;
            
//             LOAD_B : begin
//                 if (B_counter == TABLE_B_DEPTH - 1) ns = STREAM_A;
//                 else                                ns = LOAD_B;
//             end
            
//             STREAM_A : begin
//                 if (A_counter == TABLE_A_DEPTH - 1) ns = NEXT;
//                 else                                ns = STREAM_A;
//             end

//             FLUSH : begin
//                 // Wait for the math to fall out of the array (latency = TABLE_B_DEPTH)
//                 if (flush_counter == TABLE_B_DEPTH - 1) ns = NEXT;
//                 else                                    ns = FLUSH;
//             end
            
//             NEXT : begin
//                 if (dec_eop) ns = IDLE;
//                 else         ns = PREFETCH;
//             end

//             PREFETCH : ns = FETCH;

//             default : ns = IDLE;
//         endcase
//     end

//     // ==========================================
//     // BLOCK 3: OUTPUT LOGIC 
//     // ==========================================
//     always_comb begin : out_logic
        
//         // 1. INPUT ROUTING (Where does the data come from?)
//         // Only Selection (00) uses the static Immediate value from the Aligner
//         if (dec_opcode == 2'b00) begin
//             sel_data_A = 1'b1; // Route from Aligner
//         end else begin
//             sel_data_A = 1'b0; // Route straight from BRAM A
//         end

//         // 2. OUTPUT ROUTING (What format does the Host CPU want?)
//         // Intersection (10) and Difference (11) require the Scalar Accumulator
//         if (dec_opcode == 2'b10 || dec_opcode == 2'b11) begin
//             out_sel = 1'b1; // Route from Accumulator (Scalar)
//         end else begin
//             out_sel = 1'b0; // Route straight from 2D Array (Vector)
//         end

//         // 3. Accumulation Mode (Only relevant for the Accumulator)
//         if (dec_opcode == 2'b11) begin
//             accum_mode = 1'b1; // Difference Mode (Use NOR logic)
//         end else begin
//             accum_mode = 1'b0; // Intersection Mode (Use OR logic)
//         end

//         // Using your exact concatenation style for pulse signals
//         // Format: {valid_in, load_en, done_signal, accum_mode}
//         case(ps)
//             IDLE     : {valid_in_comb, load_en, done_signal} = 3'b000;
//             PREFETCH : {valid_in_comb, load_en, done_signal} = 3'b000;
//             FETCH    : {valid_in_comb, load_en, done_signal} = 3'b000;
//             DECODE   : {valid_in_comb, load_en, done_signal} = 3'b000;
//             LOAD_B   : {valid_in_comb, load_en, done_signal} = 3'b010;
//             STREAM_A : {valid_in_comb, load_en, done_signal} = 3'b100;
//             FLUSH    : {valid_in_comb, load_en, done_signal} = 3'b000; // <-- Added FLUSH (all 0s)
//             NEXT     : {valid_in_comb, load_en, done_signal} = {1'b0, 1'b0, dec_eop};
//             default  : {valid_in_comb, load_en, done_signal} = 3'b000;
//         endcase
//     end


//     // ==========================================
//     // BLOCK 4: THE ISOLATED COUNTERS
//     // ==========================================
//     // By keeping these down here, the FSM above stays perfectly clean
//     always_ff @(posedge clk) begin : counter_block
//         if (rst) begin
//             pc_reg    <= '0;
//             A_counter <= '0;
//             B_counter <= '0;
//             IR        <= '0;
//             flush_counter <= '0;
//         end else begin
//             // Instruction Register
//             if (ps == FETCH) 
//                 IR <= instruction_in;

//             // BRAM Counters
//             if (ps == LOAD_B)   
//                 B_counter <= B_counter + 1'b1;
//             else if (ps == NEXT) 
//                 B_counter <= '0; 

//             if (ps == STREAM_A) 
//                 A_counter <= A_counter + 1'b1;
//             else if (ps == NEXT) 
//                 A_counter <= '0; 

//             // Program Counter
//             if (ps == NEXT && dec_eop == 1'b0) 
//                 pc_reg <= pc_reg + 1'b1;
//             else if (ps == NEXT && dec_eop == 1'b1) 
//                 pc_reg <= '0;
            
//             //Flush Counter
//             if (ps == FLUSH) 
//                 flush_counter <= flush_counter + 1'b1;
//             else if (ps == NEXT)
//                 flush_counter <= '0;
//         end
//     end

//     // Connect the internal datapath to the physical output pins
//     assign imem_addr_out = pc_reg;
//     assign bram_addr_A   = A_counter;
//     assign bram_addr_B   = B_counter;
//     assign locked_instruction_out = IR;
    
    

// endmodule







`timescale 1ns / 1ps

module safrdo_controller #(
    parameter TABLE_A_DEPTH = 50,
    parameter TABLE_B_DEPTH = 4,
    parameter NUM_ROWS      = 50,             // array rows = join collector depth
    // ----- Derived width (do not override) ------------------------------------
    parameter int IDX_W     = $clog2(NUM_ROWS)
)(
    input  logic        clk, rst, cpu_start,
    input  logic [15:0] instruction_in, // Comes directly from CPU now, not IMEM

    // Real loaded row counts (from the bridge's load pointers). Used to bound the
    // JOIN so zero-padded empty slots are never compared (kills phantom pairs).
    input  logic [9:0]  num_a_rows, num_b_rows,

    // Notice: imem_addr_out is completely removed
    output logic [9:0]  bram_addr_A, bram_addr_B,
    output logic        valid_in, load_en, sel_data_A, done_signal, accum_mode,
    output logic [1:0]  out_sel,          // 00 Vector, 01 Scalar, 10 Join

    // ----- Join collector control ---------------------------------------------
    // Row read-out is done by the bridge at UART pace, so the controller only
    // wipes the matrix at the start of each instruction. No DRAIN sweep here.
    output logic              join_clear,    // per-instruction matrix soft reset

    output logic [15:0] locked_instruction_out
);

    // FETCH/DECODE merged into LATCH. NEXT replaced by DONE. Join no longer has a
    // drain state: the bridge reads the collector row-by-row at UART pace, so join
    // sequences exactly like intersection/difference (FLUSH -> DONE).
    typedef enum logic [2:0] {IDLE, LATCH, LOAD_B, STREAM_A, FLUSH, DONE} state_t;
    state_t ps, ns;

    // ------------------------------------------
    // INTERNAL DATAPATH (The Counters & Registers)
    // ------------------------------------------
    // Notice: pc_reg is completely removed
    logic [9:0]  A_counter, B_counter, flush_counter;
    logic [15:0] IR;

    // Combinational stream-valid, before the 1-cycle BRAM-A read-latency alignment.
    logic        valid_in_comb;

    // Decoded Instruction Wires
    logic [7:0] dec_imm;
    logic [3:0] dec_mask; 
    logic [1:0] dec_opcode;
    
    // Notice: dec_eop is removed, we don't care about it anymore
    assign dec_imm    = IR[15:8];
    assign dec_mask   = IR[5:2];
    assign dec_opcode = IR[1:0];

    // Every op that streams Table A (join / intersection / difference) is bounded
    // to the real loaded A-rows, so empty zero-slots never compare (no phantoms).
    // Selection (00) scans the immediate, not Table A, so it keeps the full depth.
    logic [9:0] stream_limit;
    always_comb begin
        if (dec_opcode == 2'b00) stream_limit = TABLE_A_DEPTH; // selection
        else                     stream_limit = num_a_rows;     // join/inter/diff
    end

    // ==========================================
    // BLOCK 1: STATE REGISTER
    // ==========================================
    always_ff @(posedge clk) begin : state_reg_block
        if (rst) 
            ps <= IDLE;
        else     
            ps <= ns;
    end

    // ==========================================
    // BLOCK 2: NEXT STATE LOGIC
    // ==========================================
    always_comb begin : ns_logic
        case(ps)
            IDLE : begin
                if (cpu_start) ns = LATCH;
                else           ns = IDLE;
            end
            
            LATCH : ns = LOAD_B; // Lock in the instruction, immediately start loading B
            
            LOAD_B : begin
                if (B_counter == TABLE_B_DEPTH - 1) ns = STREAM_A;
                else                                ns = LOAD_B;
            end
            
            STREAM_A : begin
                if (A_counter == stream_limit - 1) ns = FLUSH;
                else                               ns = STREAM_A;
            end

            FLUSH : begin
                // Once the math has drained into the collector, every op goes
                // straight to DONE. Join's matrix is read out later by the bridge.
                if (flush_counter == TABLE_B_DEPTH - 1) ns = DONE;
                else                                    ns = FLUSH;
            end

            DONE : ns = IDLE; // Fire the done signal, then immediately sleep
            
            default : ns = IDLE;
        endcase
    end

    // ==========================================
    // BLOCK 3: OUTPUT LOGIC 
    // ==========================================
    always_comb begin : out_logic
        
        // 1. INPUT ROUTING
        if (dec_opcode == 2'b00) sel_data_A = 1'b1;
        else                     sel_data_A = 1'b0;

        // 2. OUTPUT ROUTING (2-bit format selector)
        case (dec_opcode)
            2'b00:        out_sel = 2'b00; // Selection -> vector
            2'b01:        out_sel = 2'b10; // Join      -> pair stream
            2'b10, 2'b11: out_sel = 2'b01; // Inter/Diff -> scalar
            default:      out_sel = 2'b00;
        endcase

        // 3. Accumulation Mode
        if (dec_opcode == 2'b11) accum_mode = 1'b1;
        else                     accum_mode = 1'b0;

        // Using your concatenation style: {valid_in, load_en, done_signal}
        case(ps)
            IDLE       : {valid_in_comb, load_en, done_signal} = 3'b000;
            LATCH      : {valid_in_comb, load_en, done_signal} = 3'b000;
            LOAD_B     : {valid_in_comb, load_en, done_signal} = 3'b010;
            STREAM_A   : {valid_in_comb, load_en, done_signal} = 3'b100;
            FLUSH      : {valid_in_comb, load_en, done_signal} = 3'b000;
            DONE       : {valid_in_comb, load_en, done_signal} = 3'b001; // Fire DONE flag
            default    : {valid_in_comb, load_en, done_signal} = 3'b000;
        endcase
    end

    // ----- Join collector control output --------------------------------------
    assign join_clear = (ps == LATCH);           // wipe matrix before capture

    // ==========================================
    // BLOCK 4: THE ISOLATED COUNTERS
    // ==========================================
    always_ff @(posedge clk) begin : counter_block
        if (rst) begin
            A_counter     <= '0;
            B_counter     <= '0;
            IR            <= '0;
            flush_counter <= '0;
            valid_in      <= 1'b0;
        end else begin

            // Delay the array valid by 1 cycle so it lands on the same edge the
            // BRAM-A read data arrives (fixes the junk-first / dropped-last A row).
            valid_in <= valid_in_comb;

            // Latch the instruction from the host CPU directly
            if (ps == LATCH)
                IR <= instruction_in;
                
            // BRAM Counters
            if (ps == LOAD_B)   
                B_counter <= B_counter + 1'b1;
            else if (ps == DONE) 
                B_counter <= '0;
                
            if (ps == STREAM_A) 
                A_counter <= A_counter + 1'b1;
            else if (ps == DONE) 
                A_counter <= '0;
                
            // Flush Counter
            if (ps == FLUSH)
                flush_counter <= flush_counter + 1'b1;
            else if (ps == DONE)
                flush_counter <= '0;
        end
    end

    // Physical output assignments
    assign bram_addr_A   = A_counter;
    assign bram_addr_B   = B_counter;
    assign locked_instruction_out = IR;
    
endmodule