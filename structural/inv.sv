// Inverter (datapath primitive). Builds the NOR / difference path.
module inv (
    input  logic a,
    output logic y
);
    assign y = ~a;
endmodule
