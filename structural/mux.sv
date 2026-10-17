module mux (
    input   logic mask,
    input   logic and_output, match_in,
    output  logic mux_out
);

    always_comb begin
       if(mask) begin
        mux_out = and_output;
    end
    else begin
        mux_out = match_in;
    end 
    end
    


    
endmodule