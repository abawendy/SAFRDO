`timescale 1ns / 1ps

module tb_accumulation_array();

    // Parameters
    parameter NUM_ROWS = 50;

    // Testbench Signals
    logic                clk;
    logic                rst;
    logic [NUM_ROWS-1:0] row_match_out;
    logic                valid_in;
    
    logic                t_i;
    logic                valid_out;

    // Instantiate the Device Under Test (DUT)
    accumulation_array #(
        .NUM_ROWS(NUM_ROWS)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .row_match_out(row_match_out),
        .valid_in(valid_in),
        .t_i(t_i),
        .valid_out(valid_out)
    );

    // Clock Generation (10ns period -> 100MHz)
    always #5 clk = ~clk;

    // Test Sequence
    initial begin
        // 1. Initialize Signals
        clk = 0;
        rst = 1;
        row_match_out = '0;
        valid_in = 0;

        // 2. Hold Reset
        #20;
        rst = 0;
        #10;

        $display("--- Starting Accumulator Pipeline Test ---");

        // 3. Fire a Test Tuple (A match occurs at Row 0)
        // We set bit 0 high, and assert valid_in for exactly one clock cycle.
        @(posedge clk);
        row_match_out[0] = 1'b1;
        valid_in = 1'b1;
        
        @(posedge clk);
        row_match_out = '0; // Clear the match
        valid_in = 1'b0;    // Clear the valid signal

        // 4. Wait for the Pipeline to Drain (50 stages)
        // We will monitor the output every clock cycle.
        for (int cycle = 1; cycle <= 55; cycle++) begin
            @(posedge clk);
            if (valid_out) begin
                $display("Cycle %0d: SUCCESS! valid_out triggered.", cycle);
                if (t_i == 1'b1)
                    $display(" -> t_i is HIGH. The OR-reduction worked perfectly!");
                else
                    $display(" -> FAIL: t_i is LOW but should be HIGH.");
            end
        end

        $display("--- Test Complete ---");
        $stop;
    end

endmodule