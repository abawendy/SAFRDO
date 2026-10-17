module and_gate (
    input logic comp_out, match_in,
    output logic and_output
);
    assign and_output = (comp_out && match_in);
    
endmodule