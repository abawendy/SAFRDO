module operand_aligner (
    // ==========================================
    // INPUTS (Sliced directly from the Instruction)
    // ==========================================
    input  logic [1:0] opcode,  // Bits [15:14]
    input  logic [3:0] mask,    // Bits [13:10]
    input  logic [7:0] imm_in,  // Bits [7:0]

    // ==========================================
    // OUTPUT (To the Datapath MUX)
    // ==========================================
    output logic [31:0] aligned_out
);

    always_comb begin
        // The hardware safety gate: Only align data if it's a Selection op.
        if (opcode == 2'b00) begin
            
            // Look at the mask to find the target column
            case (mask)
                // Col 0 Match: Pad 24 zeros, then the 8-bit data
                4'b0001: aligned_out = { 24'h000000, imm_in };
                
                // Col 1 Match: Pad 16 zeros, data, then 8 zeros
                4'b0010: aligned_out = { 16'h0000, imm_in, 8'h00 };
                
                // Col 2 Match: Pad 8 zeros, data, then 16 zeros
                4'b0100: aligned_out = { 8'h00, imm_in, 16'h0000 };
                
                // Col 3 Match: Data, then pad 24 zeros
                4'b1000: aligned_out = { imm_in, 24'h000000 };
                
                // Fallback for invalid masks (e.g., user sends 0110)
                default: aligned_out = 32'h0000_0000;
            endcase
            
        end else begin
            // For Joins/Intersections/Differences, force output to zero.
            // This prevents random electrical noise from entering the datapath.
            aligned_out = 32'h0000_0000;
        end
    end

endmodule