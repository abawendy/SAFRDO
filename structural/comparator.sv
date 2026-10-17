module comparator #(
    parameter DATA_WIDTH = 8
) (
    input logic [DATA_WIDTH-1:0] a_in, b_in,
    input logic a_valid_in, 
    output logic comp_out
);

    assign comp_out = (a_in == b_in) && a_valid_in;

endmodule