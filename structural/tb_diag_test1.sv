`timescale 1ns / 1ps

// THROWAWAY DIAGNOSTIC TB - drives the REAL bridge over UART, exactly like
// host_script.py, then runs all 4 selection tests and checks each result the
// same way pyserial does (read 7 bytes, big-endian, mask to 50 bits).
module tb_diag_test1;

    localparam BIT_PERIOD = 8680; // ns, 115200 baud

    logic clk_100mhz = 0;
    logic reset_btn;
    logic uart_rx_pin;
    logic uart_tx_pin;

    safrdo_uart_bridge #(
        .DATA_WIDTH(32), .ADDR_WIDTH(10), .NUM_ROWS(50)
    ) DUT (
        .clk_100mhz(clk_100mhz), .reset_btn(reset_btn),
        .uart_rx_pin(uart_rx_pin), .uart_tx_pin(uart_tx_pin)
    );

    always #5 clk_100mhz = ~clk_100mhz; // 100 MHz

    // ---- Laptop -> FPGA: one byte, LSB first ----
    task send_uart_byte(input [7:0] data_byte);
        integer i;
        begin
            uart_rx_pin = 0; #(BIT_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_pin = data_byte[i]; #(BIT_PERIOD);
            end
            uart_rx_pin = 1; #(BIT_PERIOD);
            #(BIT_PERIOD * 2);
        end
    endtask

    task load_row(input [7:0] cmd,
                  input [7:0] c3, input [7:0] c2, input [7:0] c1, input [7:0] c0);
        begin
            send_uart_byte(cmd);
            send_uart_byte(c3); send_uart_byte(c2);
            send_uart_byte(c1); send_uart_byte(c0);
        end
    endtask

    // ---- FPGA -> Laptop: decode TX bytes like pyserial ----
    logic [7:0] rx_bytes [0:6];
    integer     rx_count = 0;
    integer     k;

    initial begin
        forever begin
            @(negedge uart_tx_pin);
            #(BIT_PERIOD + BIT_PERIOD/2);
            for (k = 0; k < 8; k = k + 1) begin
                if (rx_count < 7) rx_bytes[rx_count][k] = uart_tx_pin;
                #(BIT_PERIOD);
            end
            if (rx_count < 7) rx_count = rx_count + 1;
        end
    end

    integer pass_count = 0;
    integer fail_count = 0;

    // ---- Serial capture: record t_i (final_data_out[0]) each time its valid pulses ----
    reg         cap_en = 0;
    reg [63:0]  serial_vec = 0;
    integer     serial_cnt = 0;
    always @(posedge clk_100mhz) begin
        if (cap_en && DUT.final_valid_out[0]) begin
            serial_vec[serial_cnt] <= DUT.final_data_out[0];
            serial_cnt <= serial_cnt + 1;
        end
    end

    // Stream log: A-row data each cycle the array's valid_in is high (stream order)
    reg [31:0] stream_log [0:63];
    integer    stream_n = 0;
    // Emerge log: t_i each cycle the accumulator's valid_out pulses (emerge order)
    reg        emerge_log [0:63];
    integer    emerge_n = 0;
    always @(posedge clk_100mhz) begin
        if (cap_en) begin
            if (DUT.U_ACCEL.valid_wire && stream_n < 64) begin
                stream_log[stream_n] = DUT.U_ACCEL.data_a_wire;
                stream_n = stream_n + 1;
            end
            if (DUT.final_valid_out[0] && emerge_n < 64) begin
                emerge_log[emerge_n] = DUT.final_data_out[0];
                emerge_n = emerge_n + 1;
            end
        end
    end

    task run_intersect_demo(input [15:0] instr);
        integer m;
        begin
            stream_n = 0; emerge_n = 0; cap_en = 1; rx_count = 0;
            send_uart_byte(8'hEE);
            send_uart_byte(instr[15:8]);
            send_uart_byte(instr[7:0]);
            wait (rx_count == 7);
            #(BIT_PERIOD * 2);
            cap_en = 0;
            $display("  instr=0x%h  bridge result_reg = 0b%b", instr, DUT.result_reg);
            $display("  streamed %0d A-rows, emerged %0d t_i bits", stream_n, emerge_n);
            for (m = 0; m < 8 && m < stream_n; m = m + 1)
                $display("    stream[%0d] A=0x%08h   emerge[%0d] t_i=%0d", m, stream_log[m], m, emerge_log[m]);
        end
    endtask

    // ---- run one selection test and check it ----
    task run_test(input [200:0] name, input [15:0] instr, input [49:0] expected);
        reg [55:0] recon;
        reg [49:0] vec;
        begin
            rx_count = 0;
            send_uart_byte(8'hEE);
            send_uart_byte(instr[15:8]);
            send_uart_byte(instr[7:0]);
            wait (rx_count == 7);
            #(BIT_PERIOD * 2);
            recon = {rx_bytes[0], rx_bytes[1], rx_bytes[2], rx_bytes[3],
                     rx_bytes[4], rx_bytes[5], rx_bytes[6]};
            vec = recon[49:0];
            if (vec === expected) begin
                $display("  PASS  %0s  instr=0x%h  got=0b%b  (expected 0b%b)",
                         name, instr, vec[7:0], expected[7:0]);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  %0s  instr=0x%h  got=0b%b  EXPECTED 0b%b",
                         name, instr, vec[7:0], expected[7:0]);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Emulate Artix-7 BRAM power-up state (all zeros), so unused rows 4..49
    // don't read as X. On real hardware this is automatic.
    integer z;
    initial begin
        for (z = 0; z < 60; z = z + 1) begin
            DUT.U_ACCEL.U_BRAM_B.ram[z] = 32'h0;
            DUT.U_ACCEL.U_BRAM_A.ram[z] = 32'h0;
        end
    end

    initial begin
        reset_btn = 1; uart_rx_pin = 1;
        #200; reset_btn = 0; #200;

        $display("\n=== Full UART flow through the FIXED bridge (NUM_ROWS=50) ===");

        send_uart_byte(8'hFF); // reset pointers

        // table_B.csv -> BRAM B
        load_row(8'hBB, 8'd10, 8'd255, 8'd30, 8'd40);
        load_row(8'hBB, 8'd99, 8'd99,  8'd99, 8'd99);
        load_row(8'hBB, 8'd11, 8'd255, 8'd33, 8'd44);
        load_row(8'hBB, 8'd0,  8'd0,   8'd0,  8'd0);

        // table_A.csv -> BRAM A
        load_row(8'hAA, 8'd10,  8'd255, 8'd30,  8'd40);
        load_row(8'hAA, 8'd1,   8'd2,   8'd3,   8'd4);
        load_row(8'hAA, 8'd99,  8'd99,  8'd99,  8'd99);
        load_row(8'hAA, 8'd100, 8'd100, 8'd100, 8'd100);
        load_row(8'hAA, 8'd11,  8'd255, 8'd33,  8'd44);
        load_row(8'hAA, 8'd0,   8'd0,   8'd0,   8'd0);

        $display("--- BRAM B after load (row 0 must now be at addr 0) ---");
        for (k = 0; k < 5; k = k + 1)
            $display("  ram_B[%0d] = 0x%h", k, DUT.U_ACCEL.U_BRAM_B.ram[k]);

        $display("--- Selection tests ---");
        run_test("Test1 Col3==10 ", 16'h0A20, 50'h1); // row 0
        run_test("Test2 Col2==255", 16'hFF10, 50'h5); // rows 0 and 2 -> 0b101
        run_test("Test3 Col1==30 ", 16'h1E08, 50'h1); // row 0
        run_test("Test4 Col0==40 ", 16'h2804, 50'h1); // row 0

        // ---- Intersection (opcode 10b=2). Scalar result: 1 = tables share a tuple ----
        // A and B both contain [10,255,30,40], [99,99,99,99], [11,255,33,44], [0,0,0,0]
        // mask=1111 (full row): instr = (0<<8)|(15<<2)|2 = 0x003E
        // mask=0100 (col2 only): instr = (0<<8)|(4<<2)|2  = 0x0012
        $display("--- Intersection now returns a PER-A-ROW vector (bit i = A row i is in B) ---");
        $display("    A rows: 0=[10,255,30,40] 1=[1,2,3,4] 2=[99,99,99,99] 3=[100,100,100,100] 4=[11,255,33,44] 5..=[0,0,0,0]");
        $display("    in B?:  0=YES            1=NO        2=YES           3=NO                  4=YES          5..=YES(zero rows)");
        $display("    bounded to the 6 real A-rows: A0,A2,A4,A5 in B, A1,A3 not -> 0b110101 = 0x35");
        run_intersect_demo(16'h003E); // prints full result_reg + trace
        run_test("Intersect full ", 16'h003E, 50'h35);
        run_test("Intersect Col2 ", 16'h0012, 50'h35); // col2: A1(=2),A3(=100) not in B's col2 either

        $display("\n=== %0d passed, %0d failed ===\n", pass_count, fail_count);
        $finish;
    end

    initial begin
        #(BIT_PERIOD * 3000);
        $display("TIMEOUT (rx_count=%0d)", rx_count);
        $finish;
    end

endmodule
