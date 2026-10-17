`timescale 1ns / 1ps

module tb_safrdo_uart_bridge;

    // ==========================================
    // 1. HARDWARE PARAMETERS
    // ==========================================
    parameter CLK_FREQ   = 100_000_000; 
    parameter BAUD_RATE  = 115200;
    
    // (1,000,000,000 ns / 115200 = ~8680 ns per bit)
    localparam BIT_PERIOD = 8680; 

    // ==========================================
    // 2. PHYSICAL PINS
    // ==========================================
    logic clk_100mhz;
    logic reset_btn;
    logic uart_rx_pin; // Laptop -> FPGA
    logic uart_tx_pin; // FPGA -> Laptop

    // ==========================================
    // 3. DUT INSTANTIATION
    // ==========================================
    safrdo_uart_bridge #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10),
        .NUM_ROWS(4)
    ) DUT (
        .clk_100mhz (clk_100mhz),
        .reset_btn  (reset_btn),
        .uart_rx_pin(uart_rx_pin),
        .uart_tx_pin(uart_tx_pin)
    );

    // ==========================================
    // 4. CLOCK GENERATION
    // ==========================================
    always #5 clk_100mhz = ~clk_100mhz; // 10ns period

    // ==========================================
    // 5. UART TRANSMISSION TASK (The "Laptop")
    // ==========================================
    task send_uart_byte(input [7:0] data_byte);
        integer i;
        begin
            // Start Bit
            uart_rx_pin = 0;
            #(BIT_PERIOD);
            
            // 8 Data Bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_pin = data_byte[i];
                #(BIT_PERIOD);
            end
            
            // Stop Bit
            uart_rx_pin = 1;
            #(BIT_PERIOD);
            
            // Tiny pause between bytes
            #(BIT_PERIOD * 2); 
        end
    endtask

    // ==========================================
    // 6. MAIN SIMULATION SEQUENCE
    // ==========================================
    initial begin
        // --- STEP A: Power On & Reset ---
        $display("Starting UART Bridge Simulation...");
        clk_100mhz = 0;
        uart_rx_pin = 1; // UART lines idle HIGH
        reset_btn = 1;
        #100;
        reset_btn = 0;
        #100;

        // --- STEP B: Load a Tuple into BRAM A ---
        $display("Sending Command 0xAA (Load BRAM A)...");
        send_uart_byte(8'hAA); // Your FSM expects this first!
        
        $display("Sending Data Bytes (10, 20, 30, 40)...");
        send_uart_byte(8'h10); 
        send_uart_byte(8'h20); 
        send_uart_byte(8'h30); 
        send_uart_byte(8'h40); 
        
        // Give the FSM a moment to process the write
        #(BIT_PERIOD * 5); 

        // --- STEP C: Send the Instruction ---
        $display("Sending Command 0xEE (Execute Instruction)...");
        send_uart_byte(8'hEE); // Tell FSM to expect an instruction next
        
        $display("Sending Instruction Bytes (FF, 10)...");
        send_uart_byte(8'hFF); // Upper byte
        send_uart_byte(8'h10); // Lower byte
        
        // --- STEP D: Wait for Result ---
        $display("Waiting for hardware to execute and transmit results...");
        
        // The hardware will now execute the math and then automatically 
        // transition to SEND_RESULT to push the 7 bytes out via uart_tx_pin.
        // We just need to keep the simulation running long enough to see it.
        #(BIT_PERIOD * 100);

        $display("Simulation Complete!");
        $stop;
    end

endmodule