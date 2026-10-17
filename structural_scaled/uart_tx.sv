`timescale 1ns / 1ps

module uart_tx #(
    parameter CLKS_PER_BIT = 868 // 100 MHz / 115200 Baud
)(
    input  logic clk,
    input  logic reset,
    input  logic tx_start,       // Pulse high to start transmission
    input  logic [7:0] tx_data,  // The byte to send
    
    output logic tx_busy,        // High while sending
    output logic tx              // The physical TX pin
);

    typedef enum logic [2:0] {IDLE, START, DATA, STOP, CLEANUP} state_t;
    state_t state;

    logic [$clog2(CLKS_PER_BIT)-1:0] clk_count;
    logic [2:0] bit_index;
    logic [7:0] tx_shift_reg;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            tx <= 1'b1; // UART idles HIGH
            tx_busy <= 1'b0;
            clk_count <= '0;
            bit_index <= '0;
            tx_shift_reg <= '0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    tx_busy <= 1'b0;
                    clk_count <= '0;
                    bit_index <= '0;
                    
                    if (tx_start) begin
                        tx_shift_reg <= tx_data;
                        tx_busy <= 1'b1;
                        state <= START;
                    end
                end
                
                START: begin
                    tx <= 1'b0; // Start bit is LOW
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= '0;
                        state <= DATA;
                    end
                end
                
                DATA: begin
                    tx <= tx_shift_reg[bit_index]; // Send LSB first
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= '0;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1'b1;
                        end else begin
                            state <= STOP;
                        end
                    end
                end
                
                STOP: begin
                    tx <= 1'b1; // Stop bit is HIGH
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= '0;
                        state <= CLEANUP;
                    end
                end
                
                CLEANUP: begin
                    // 1 cycle gap to ensure clean transitions
                    tx_busy <= 1'b0;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule