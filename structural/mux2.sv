// Generic 1-bit 2:1 multiplexer (datapath primitive).
//   sel = 0 -> d0,  sel = 1 -> d1
module mux2 (
    input  logic sel,
    input  logic d0,
    input  logic d1,
    output logic y
);
    assign y = sel ? d1 : d0;
endmodule
