module breg #(
    parameter DATA_WIDTH = 8
) (
    input logic clk, rst, load_en,
    input logic [DATA_WIDTH-1:0] b_in,
    output logic [DATA_WIDTH-1:0] b_pass
);

    always_ff @(posedge clk) begin
        if(rst) begin
            b_pass <= '0;
        end
        else if(load_en) begin
            b_pass <= b_in;
        end
        else begin
            b_pass <= b_pass;
        end

    end
    
endmodule