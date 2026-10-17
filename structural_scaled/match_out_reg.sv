module match_out_reg  (
    input logic clk, rst,
    input logic mux_out,
    output logic match_out
);

    always_ff @(posedge clk) begin
        if(rst) begin
            match_out <= '0;
        end
        else begin
            match_out <= mux_out;
        end

    end
    
endmodule