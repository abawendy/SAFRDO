module areg #(
    parameter DATA_WIDTH = 8
) (
    input logic clk, rst,
    input logic [DATA_WIDTH-1:0] a_in,
    input logic a_valid_in,
    output logic [DATA_WIDTH-1:0] a_out,
    output logic a_valid_out
);

    always_ff @(posedge clk) begin
        if(rst) begin
            a_out <= '0;
            a_valid_out <= 1'b0;
        end
        else begin
            a_out <= a_in;
            a_valid_out <= a_valid_in;
        end

    end
    
endmodule