`timescale 1ns / 1ps
// Throwaway equivalence check: behavioural accumulation_array (golden) vs the
// PE-array build accumulation_array_pe. Identical inputs every cycle -> outputs
// must match on every clock. Any divergence is a real logic difference.
module tb_accum_pe_equiv;

    localparam NUM_ROWS = 50;

    logic clk = 0, rst;
    logic [NUM_ROWS-1:0] row_match_out;
    logic valid_in, accum_mode;

    logic t_i_g, vo_g;   // golden (behavioural)
    logic t_i_d, vo_d;   // DUT (PE-array)

    accumulation_array #(.NUM_ROWS(NUM_ROWS)) GOLD (
        .clk(clk), .rst(rst), .row_match_out(row_match_out),
        .valid_in(valid_in), .accum_mode(accum_mode),
        .t_i(t_i_g), .valid_out(vo_g)
    );

    accumulation_array_pe #(.NUM_ROWS(NUM_ROWS)) DUT (
        .clk(clk), .rst(rst), .row_match_out(row_match_out),
        .valid_in(valid_in), .accum_mode(accum_mode),
        .t_i(t_i_d), .valid_out(vo_d)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer i;

    initial begin
        rst = 1; row_match_out = '0; valid_in = 0; accum_mode = 0;
        @(posedge clk); @(posedge clk);
        @(negedge clk); rst = 0;

        for (i = 0; i < 3000; i = i + 1) begin
            row_match_out = {$random, $random};
            valid_in      = $random;
            accum_mode    = $random;
            @(posedge clk);
            #1;
            if (t_i_g !== t_i_d || vo_g !== vo_d) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("MISMATCH @%0t  t_i g=%b d=%b | valid g=%b d=%b",
                             $time, t_i_g, t_i_d, vo_g, vo_d);
            end
            @(negedge clk);
        end

        if (errors == 0)
            $display("\n=== PE-CHAIN EQUIVALENT: 3000 cycles, 0 mismatches ===\n");
        else
            $display("\n=== NOT EQUIVALENT: %0d mismatches ===\n", errors);
        $finish;
    end

endmodule
