`timescale 1ns / 1ps

module uart_echo_top (
    input  logic clk_100mhz,   // 100MHz clock
    input  logic reset_btn,    // Center button
    input  logic uart_rx_pin,  // Data FROM PC
    
    output logic uart_tx_pin   // Data TO PC 
);

    // Internal wires connecting the RX directly to the TX
    logic [7:0] data_byte;
    logic byte_ready;
    logic tx_busy;

    // --- The Ears ---
    uart_rx #(
        .CLKS_PER_BIT(868) 
    ) rx_inst (
        .clk(clk_100mhz),
        .reset(reset_btn),
        .rx(uart_rx_pin),
        .rx_data(data_byte),    // Output the received byte
        .rx_ready(byte_ready)   // Pulse when ready
    );

    // --- The Mouth ---
    uart_tx #(
        .CLKS_PER_BIT(868)
    ) tx_inst (
        .clk(clk_100mhz),
        .reset(reset_btn),
        .tx_start(byte_ready),  // Use the RX ready pulse to instantly trigger TX!
        .tx_data(data_byte),    // Feed the received byte straight to the transmitter
        .tx_busy(tx_busy),
        .tx(uart_tx_pin)
    );

endmodule