`timescale 1ns / 1ps
// Throwaway equivalence check: behavioural accumulation_array  vs  the new
// structural accumulation_array_struct. Both get the SAME inputs every cycle;
// since both start from reset (all zeros) and are deterministic, their outputs
// must match on every single clock. Any divergence is a real logic difference.
module tb_accum_equiv;

    localparam NUM_ROWS = 50;

    logic clk = 0, rst;
    logic [NUM_ROWS-1:0] row_match_out;
    logic valid_in, accum_mode;

    logic t_i_gold, vo_gold;   // behavioural (golden)
    logic t_i_dut,  vo_dut;    // structural

    accumulation_array #(.NUM_ROWS(NUM_ROWS)) GOLD (
        .clk(clk), .rst(rst), .row_match_out(row_match_out),
        .valid_in(valid_in), .accum_mode(accum_mode),
        .t_i(t_i_gold), .valid_out(vo_gold)
    );

    accumulation_array_struct #(.NUM_ROWS(NUM_ROWS)) DUT (
        .clk(clk), .rst(rst), .row_match_out(row_match_out),
        .valid_in(valid_in), .accum_mode(accum_mode),
        .t_i(t_i_dut), .valid_out(vo_dut)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer i;

    initial begin
        rst = 1; row_match_out = '0; valid_in = 0; accum_mode = 0;
        @(posedge clk); @(posedge clk);
        @(negedge clk); rst = 0;

        for (i = 0; i < 3000; i = i + 1) begin
            // New random stimulus on the falling edge (settles before posedge)
            row_match_out = {$random, $random};   // 64 bits -> truncated to 50
            valid_in      = $random;
            accum_mode    = $random;
            @(posedge clk);
            #1; // let combinational mode-mux settle
            if (t_i_gold !== t_i_dut || vo_gold !== vo_dut) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("MISMATCH @%0t  t_i gold=%b dut=%b | valid gold=%b dut=%b",
                             $time, t_i_gold, t_i_dut, vo_gold, vo_dut);
            end
            @(negedge clk);
        end

        if (errors == 0)
            $display("\n=== EQUIVALENT: 3000 cycles, 0 mismatches ===\n");
        else
            $display("\n=== NOT EQUIVALENT: %0d mismatches ===\n", errors);
        $finish;
    end

endmodule
