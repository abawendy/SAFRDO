`timescale 1ns / 1ps
// =============================================================================
// tb_scaled.sv  --  full-system self-checking testbench for the 100-row build
// -----------------------------------------------------------------------------
// Drives safrdo_top directly (playing the role of the UART bridge), loads the
// 100-row coded tables from A_codes.mem / B_codes.mem, then runs all four
// operations and checks each against the values produced by gen_scaled_data.py:
//
//   Selection City=Accra : vector 0x0200020002000200020002001  (rows 0,13,29,45,61,77,93)
//   Intersection         : 10 rows {0..9}
//   Join full-row        : 10 pairs
//   Join on City         : 628 pairs
//
// Instruction encodings (imm<<8 | mask<<2 | opcode):
//   Selection City : 16'h0110  (imm=accra_code=1, mask=Col2=0100, op=00)
//   Intersection   : 16'h003E  (mask=1111, op=10)
//   Join full-row  : 16'h003D  (mask=1111, op=01)
//   Join on City   : 16'h0011  (mask=0100, op=01)
// =============================================================================
module tb_scaled;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 10;
    localparam NUM_ROWS   = 100;
    localparam int IDX_W   = $clog2(NUM_ROWS);

    logic clk, rst, cpu_start, done_signal;
    logic [15:0]           cpu_instruction;
    logic [9:0]            num_a_rows, num_b_rows;
    logic [IDX_W-1:0]      join_row_sel;
    logic                  cpu_we_A, cpu_we_B;
    logic [ADDR_WIDTH-1:0] cpu_addr_A, cpu_addr_B;
    logic [DATA_WIDTH-1:0] cpu_data_A, cpu_data_B;
    logic [NUM_ROWS-1:0]   final_data_out, final_valid_out;

    safrdo_top #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .NUM_ROWS(NUM_ROWS)) DUT (
        .clk(clk), .rst(rst), .cpu_start(cpu_start), .done_signal(done_signal),
        .cpu_instruction(cpu_instruction),
        .num_a_rows(num_a_rows), .num_b_rows(num_b_rows), .join_row_sel(join_row_sel),
        .cpu_we_A(cpu_we_A), .cpu_addr_A(cpu_addr_A), .cpu_data_A(cpu_data_A),
        .cpu_we_B(cpu_we_B), .cpu_addr_B(cpu_addr_B), .cpu_data_B(cpu_data_B),
        .final_data_out(final_data_out), .final_valid_out(final_valid_out)
    );

    always #5 clk = ~clk;

    // memory images
    logic [31:0] amem [0:NUM_ROWS-1];
    logic [31:0] bmem [0:NUM_ROWS-1];

    // ---- gated result captures (mirror the bridge) ----
    logic [NUM_ROWS-1:0] sel_acc;   logic sel_en;      // selection: OR over the run
    logic [NUM_ROWS-1:0] inter_res; logic inter_en;    // intersection: 1 bit per A row
    logic [IDX_W:0]      inter_ptr;

    always_ff @(posedge clk) begin
        if (!sel_en) sel_acc <= '0;
        else         sel_acc <= sel_acc | (final_data_out & final_valid_out);
    end
    always_ff @(posedge clk) begin
        if (!inter_en) begin inter_res <= '0; inter_ptr <= '0; end
        else if (final_valid_out[0] && inter_ptr < NUM_ROWS) begin
            inter_res[inter_ptr] <= final_data_out[0];
            inter_ptr <= inter_ptr + 1'b1;
        end
    end

    // expected constants (from gen_scaled_data.py)
    localparam [NUM_ROWS-1:0] SEL_VEC   = 100'h0200020002000200020002001;
    localparam int EXP_INTER = 10;
    localparam int EXP_JFULL = 10;
    localparam int EXP_JCITY = 628;

    integer errors = 0;
    integer b, p, cnt, k, popc;

    task automatic load_tables;
        begin
            for (k = 0; k < NUM_ROWS; k = k + 1) begin
                cpu_we_B = 1; cpu_addr_B = k[ADDR_WIDTH-1:0]; cpu_data_B = bmem[k]; #10;
            end
            cpu_we_B = 0;
            for (k = 0; k < NUM_ROWS; k = k + 1) begin
                cpu_we_A = 1; cpu_addr_A = k[ADDR_WIDTH-1:0]; cpu_data_A = amem[k]; #10;
            end
            cpu_we_A = 0;
        end
    endtask

    // run one instruction; return after the done pulse + a settle margin
    task automatic run_op(input [15:0] instr);
        begin
            cpu_instruction = instr; #20;
            cpu_start = 1; #10; cpu_start = 0;
            wait (done_signal == 1'b1);
            #40;
        end
    endtask

    // count join pairs by walking the collector rows (host-side expansion)
    task automatic count_join(output integer pairs);
        begin
            pairs = 0;
            for (b = 0; b < NUM_ROWS; b = b + 1) begin
                join_row_sel = b[IDX_W-1:0]; #10;      // settle 100:1 mux + router
                for (p = 0; p < NUM_ROWS; p = p + 1)   // n_a = NUM_ROWS
                    if (final_data_out[p]) pairs = pairs + 1;
            end
        end
    endtask

    initial begin
        clk = 0; rst = 1; cpu_start = 0; cpu_instruction = 0;
        cpu_we_A = 0; cpu_addr_A = 0; cpu_data_A = 0;
        cpu_we_B = 0; cpu_addr_B = 0; cpu_data_B = 0;
        num_a_rows = NUM_ROWS; num_b_rows = NUM_ROWS; join_row_sel = 0;
        sel_en = 0; inter_en = 0;
        $readmemh("A_codes.mem", amem);
        $readmemh("B_codes.mem", bmem);
        #20; rst = 0; #20;

        load_tables();

        // ---- TEST 1: SELECTION City = Accra ----
        sel_en = 1;
        run_op(16'h0110);
        #20; sel_en = 0;
        if (sel_acc === SEL_VEC) $display("PASS  Selection City=Accra");
        else begin errors=errors+1; $display("FAIL  Selection: got %h expected %h", sel_acc, SEL_VEC); end

        // ---- TEST 2: INTERSECTION ----
        inter_en = 1;
        run_op(16'h003E);
        #100; inter_en = 0;              // let the serial scalar drain
        popc = 0;
        for (k = 0; k < NUM_ROWS; k = k + 1) if (inter_res[k]) popc = popc + 1;
        if (popc == EXP_INTER && inter_res[EXP_INTER-1:0] == {EXP_INTER{1'b1}})
            $display("PASS  Intersection: %0d rows", popc);
        else begin errors=errors+1; $display("FAIL  Intersection: %0d rows (expected %0d), bits=%h", popc, EXP_INTER, inter_res); end

        // ---- TEST 3: JOIN full-row ----
        run_op(16'h003D);
        count_join(cnt);
        if (cnt == EXP_JFULL) $display("PASS  Join full-row: %0d pairs", cnt);
        else begin errors=errors+1; $display("FAIL  Join full-row: %0d pairs (expected %0d)", cnt, EXP_JFULL); end

        // ---- TEST 4: JOIN on City ----
        run_op(16'h0011);
        count_join(cnt);
        if (cnt == EXP_JCITY) $display("PASS  Join City: %0d pairs", cnt);
        else begin errors=errors+1; $display("FAIL  Join City: %0d pairs (expected %0d)", cnt, EXP_JCITY); end

        $display("------------------------------------------------");
        if (errors == 0) $display("SCALED (NUM_ROWS=100) FULL-SYSTEM TEST: ALL PASS");
        else             $display("SCALED TEST: %0d FAILURE(S)", errors);
        $stop;
    end

endmodule
