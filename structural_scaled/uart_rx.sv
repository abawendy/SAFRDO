`timescale 1ns / 1ps

module uart_rx #(
    parameter CLKS_PER_BIT = 868 // For 100MHz Clock and 115200 Baud
)(
    input  logic clk,
    input  logic reset,
    input  logic rx,             // The physical RX pin
    
    output logic [7:0] rx_data,  // The assembled byte
    output logic rx_ready        // Pulses high for 1 cycle when valid
);

    typedef enum logic [2:0] {IDLE, START, DATA, STOP, CLEANUP} state_t;
    state_t state, next_state;

    logic [$clog2(CLKS_PER_BIT)-1:0] clk_count;
    logic [2:0] bit_index; // 0 to 7
    logic [7:0] rx_shift_reg;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            clk_count <= '0;
            bit_index <= '0;
            rx_data <= '0;
            rx_ready <= 1'b0;
        end else begin
            rx_ready <= 1'b0; // Default to 0, pulse only when complete
            
            case (state)
                IDLE: begin
                    clk_count <= '0;
                    bit_index <= '0;
                    if (rx == 1'b0) // Start bit detected (UART idles high)
                        state <= START;
                end
                
                START: begin
                    // Wait to reach the middle of the start bit to sample safely
                    if (clk_count == (CLKS_PER_BIT / 2)) begin
                        if (rx == 1'b0) begin
                            clk_count <= '0;
                            state <= DATA;
                        end else begin
                            state <= IDLE; // False start
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                
                DATA: begin
                    // Wait a full bit width to sample the middle of the data bits
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= '0;
                        rx_shift_reg[bit_index] <= rx; // Sample the bit
                        
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1'b1;
                        end else begin
                            state <= STOP;
                        end
                    end
                end
                
                STOP: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        rx_data <= rx_shift_reg;
                        rx_ready <= 1'b1; // Pulse ready!
                        state <= CLEANUP;
                    end
                end
                
                CLEANUP: begin
                    state <= IDLE; // 1 cycle gap before next byte
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule