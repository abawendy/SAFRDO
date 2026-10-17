`timescale 1ns / 1ps
// =============================================================================
// tb_join_readout.sv
// -----------------------------------------------------------------------------
// Verifies the NEW row-wise JOIN read-out. The testbench plays the role of the
// UART bridge: it loads B and A, issues a full-row JOIN, waits for done, then
// walks join_row_sel across the B-rows and reads each row's 50-bit (here 4-bit)
// match vector off final_data_out. It expands the vectors into (A,B) pairs and
// checks them against the hand-computed expected set.
//
// Tables (4 cols x 8 bits, packed {c3,c2,c1,c0}):
//   B0={10,20,30,40}  B1={50,60,70,80}  B2={11,22,33,44}  B3={99,99,99,99}
//   A0={10,20,30,40}  A1={11,22,33,44}  A2={50,60,70,80}  A3={1,2,3,4}
// Full-row matches: A0=B0, A1=B2, A2=B1, A3=none.
//   sr[b][p] = match(A_{n_a-1-p}, B_b),  so expected row vectors (n_a=4):
//   row0=4'b1000 (A0)  row1=4'b0010 (A2)  row2=4'b0100 (A1)  row3=4'b0000
// =============================================================================
module tb_join_readout;

    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 10;
    parameter NUM_ROWS   = 4;

    logic clk, rst, cpu_start, done_signal;
    logic [15:0]           cpu_instruction;
    logic [9:0]            num_a_rows, num_b_rows;
    localparam int IDX_W = $clog2(NUM_ROWS);
    logic [IDX_W-1:0]      join_row_sel;

    logic                  cpu_we_A;
    logic [ADDR_WIDTH-1:0] cpu_addr_A;
    logic [DATA_WIDTH-1:0] cpu_data_A;
    logic                  cpu_we_B;
    logic [ADDR_WIDTH-1:0] cpu_addr_B;
    logic [DATA_WIDTH-1:0] cpu_data_B;

    logic [NUM_ROWS-1:0]   final_data_out, final_valid_out;

    safrdo_top #(
        .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .NUM_ROWS(NUM_ROWS)
    ) DUT (
        .clk(clk), .rst(rst),
        .cpu_start(cpu_start), .done_signal(done_signal),
        .cpu_instruction(cpu_instruction),
        .num_a_rows(num_a_rows), .num_b_rows(num_b_rows),
        .join_row_sel(join_row_sel),
        .cpu_we_A(cpu_we_A), .cpu_addr_A(cpu_addr_A), .cpu_data_A(cpu_data_A),
        .cpu_we_B(cpu_we_B), .cpu_addr_B(cpu_addr_B), .cpu_data_B(cpu_data_B),
        .final_data_out(final_data_out), .final_valid_out(final_valid_out)
    );

    always #5 clk = ~clk;

    // Expected per-row match vectors and the tallies we build from them.
    logic [NUM_ROWS-1:0] exp_vec [NUM_ROWS];
    logic [NUM_ROWS-1:0] got_vec [NUM_ROWS];
    integer errors;
    integer b, p, a_idx;

    task write_b(input [ADDR_WIDTH-1:0] addr, input [7:0] c3,c2,c1,c0);
        begin
            cpu_we_B = 1; cpu_addr_B = addr;
            cpu_data_B = {c3,c2,c1,c0}; #10;
        end
    endtask
    task write_a(input [ADDR_WIDTH-1:0] addr, input [7:0] c3,c2,c1,c0);
        begin
            cpu_we_A = 1; cpu_addr_A = addr;
            cpu_data_A = {c3,c2,c1,c0}; #10;
        end
    endtask

    initial begin
        clk = 0; rst = 1; cpu_start = 0; cpu_instruction = 16'h0000;
        cpu_we_A = 0; cpu_addr_A = 0; cpu_data_A = 0;
        cpu_we_B = 0; cpu_addr_B = 0; cpu_data_B = 0;
        num_a_rows = 4; num_b_rows = 4; join_row_sel = 0;
        errors = 0;
        #20; rst = 0; #20;

        // --- Load resident table B ---
        write_b(0, 8'd10,8'd20,8'd30,8'd40);
        write_b(1, 8'd50,8'd60,8'd70,8'd80);
        write_b(2, 8'd11,8'd22,8'd33,8'd44);
        write_b(3, 8'd99,8'd99,8'd99,8'd99);
        cpu_we_B = 0;

        // --- Load streaming table A ---
        write_a(0, 8'd10,8'd20,8'd30,8'd40);
        write_a(1, 8'd11,8'd22,8'd33,8'd44);
        write_a(2, 8'd50,8'd60,8'd70,8'd80);
        write_a(3, 8'd1, 8'd2, 8'd3, 8'd4);
        cpu_we_A = 0;

        // Expected row vectors (see header)
        exp_vec[0] = 4'b1000;
        exp_vec[1] = 4'b0010;
        exp_vec[2] = 4'b0100;
        exp_vec[3] = 4'b0000;

        // --- Issue full-row JOIN: imm=0, mask=1111, opcode=01 -> 16'h003D ---
        cpu_instruction = 16'h003D; #10;
        #20; cpu_start = 1; #10; cpu_start = 0;

        wait(done_signal == 1'b1);
        #20; // let the FSM settle back to IDLE (IR still holds JOIN -> out_sel=10)

        // --- Play the bridge: walk B-rows, read each row's match vector ---
        for (b = 0; b < 4; b = b + 1) begin
            join_row_sel = b[IDX_W-1:0];
            #10;                       // let the 50:1 mux + router settle
            got_vec[b] = final_data_out;
            if (got_vec[b] !== exp_vec[b]) begin
                errors = errors + 1;
                $display("  ROW %0d MISMATCH: got %b  expected %b", b, got_vec[b], exp_vec[b]);
            end else
                $display("  ROW %0d ok: %b", b, got_vec[b]);
        end

        // --- Expand vectors into pairs (host would do this) ---
        $display("--- JOIN pairs (A,B) ---");
        for (b = 0; b < 4; b = b + 1)
            for (p = 0; p < num_a_rows; p = p + 1)
                if (got_vec[b][p]) begin
                    a_idx = num_a_rows - 1 - p;
                    $display("   A%0d <-> B%0d", a_idx, b);
                end

        if (errors == 0) $display("JOIN READOUT TEST: PASS");
        else             $display("JOIN READOUT TEST: FAIL (%0d row mismatches)", errors);
        $stop;
    end

endmodule
