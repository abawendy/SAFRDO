// 1-bit D flip-flop with synchronous reset.
// Generic datapath register primitive (draws as a single clocked box).
module dff (
    input  logic clk,
    input  logic rst,
    input  logic d,
    output logic q
);
    always_ff @(posedge clk) begin
        if (rst) q <= 1'b0;
        else     q <= d;
    end
endmodule
