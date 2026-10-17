`timescale 1ns / 1ps

// Throwaway end-to-end TB for the JOIN op. Drives the REAL bridge over UART like
// host_script.py, loads the two tables, and fires two joins:
//   1. full-column (mask 15): all 4 columns must match
//   2. Column-2 only (mask 4): pair rows that share a Col2 value
// Decodes the variable-length pair stream: byte 0 = count, then A,B per pair.
module tb_join;

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

    // ---- FPGA -> Laptop: capture the whole pair stream (variable length) ----
    logic [7:0] jbytes [0:63];
    integer     jn = 0;
    integer     b;

    initial begin
        forever begin
            @(negedge uart_tx_pin);
            #(BIT_PERIOD + BIT_PERIOD/2);
            for (b = 0; b < 8; b = b + 1) begin
                if (jn < 64) jbytes[jn][b] = uart_tx_pin;
                #(BIT_PERIOD);
            end
            if (jn < 64) jn = jn + 1;
        end
    end

    // ---- captured pairs from the most recent join ----
    logic [7:0] got_a [0:63];
    logic [7:0] got_b [0:63];
    integer     got_count;

    task run_join(input [15:0] instr);
        integer total, q;
        begin
            jn = 0;
            send_uart_byte(8'hEE);
            send_uart_byte(instr[15:8]);
            send_uart_byte(instr[7:0]);
            wait (jn >= 1);                 // header (count) arrives first
            total = 1 + 2*jbytes[0];
            wait (jn >= total);             // then 2 bytes per pair
            #(BIT_PERIOD * 2);
            got_count = jbytes[0];
            $display("  instr=0x%h -> %0d pair(s):", instr, got_count);
            for (q = 0; q < got_count && q < 64; q = q + 1) begin
                got_a[q] = jbytes[1 + 2*q];
                got_b[q] = jbytes[2 + 2*q];
                $display("      A%0d <-> B%0d", got_a[q], got_b[q]);
            end
        end
    endtask

    // Emulate Artix-7 BRAM power-up state (all zeros) for the unused rows.
    integer z;
    initial begin
        for (z = 0; z < 60; z = z + 1) begin
            DUT.U_ACCEL.U_BRAM_B.ram[z] = 32'h0;
            DUT.U_ACCEL.U_BRAM_A.ram[z] = 32'h0;
        end
    end

    integer pass_count = 0;
    integer fail_count = 0;
    integer p;

    // Expected pair sets (emission order: B outer 0..N_B-1, A-index descending)
    logic [7:0] exp_a [0:7];
    logic [7:0] exp_b [0:7];
    integer     exp_n;

    task check(input [200:0] name);
        integer ok;
        begin
            ok = (got_count === exp_n);
            for (p = 0; p < exp_n && p < got_count; p = p + 1)
                if (got_a[p] !== exp_a[p] || got_b[p] !== exp_b[p]) ok = 0;
            if (ok) begin
                $display("  PASS  %0s  (%0d pairs match)", name, exp_n);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  %0s  got %0d pairs, expected %0d", name, got_count, exp_n);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        reset_btn = 1; uart_rx_pin = 1;
        #200; reset_btn = 0; #200;

        $display("\n=== JOIN end-to-end ===");

        send_uart_byte(8'hFF); // reset pointers

        // table_B.csv -> BRAM B  (4 real rows)
        load_row(8'hBB, 8'd10, 8'd255, 8'd30, 8'd40);
        load_row(8'hBB, 8'd99, 8'd99,  8'd99, 8'd99);
        load_row(8'hBB, 8'd11, 8'd255, 8'd33, 8'd44);
        load_row(8'hBB, 8'd0,  8'd0,   8'd0,  8'd0);

        // table_A.csv -> BRAM A  (6 real rows)
        load_row(8'hAA, 8'd10,  8'd255, 8'd30,  8'd40);
        load_row(8'hAA, 8'd1,   8'd2,   8'd3,   8'd4);
        load_row(8'hAA, 8'd99,  8'd99,  8'd99,  8'd99);
        load_row(8'hAA, 8'd100, 8'd100, 8'd100, 8'd100);
        load_row(8'hAA, 8'd11,  8'd255, 8'd33,  8'd44);
        load_row(8'hAA, 8'd0,   8'd0,   8'd0,   8'd0);

        // ---- TEST 1: full-column join (mask 1111 = 15) -> instr 0x3D ----
        $display("--- Join (full row, all columns) ---");
        exp_a[0]=0; exp_a[1]=2; exp_a[2]=4; exp_a[3]=5;
        exp_b[0]=0; exp_b[1]=1; exp_b[2]=2; exp_b[3]=3;
        exp_n = 4;
        run_join(16'h003D);
        check("Join full-column");

        // ---- TEST 2: Column-2 join (mask 0100 = 4) -> instr 0x11 ----
        // Col2 values: A=[255,2,99,100,255,0], B=[255,99,255,0].
        // Per B-row, A-index descending:
        //   B0(255): A4,A0   B1(99): A2   B2(255): A4,A0   B3(0): A5
        $display("--- Join (Column 2 only) ---");
        exp_a[0]=4; exp_a[1]=0; exp_a[2]=2; exp_a[3]=4; exp_a[4]=0; exp_a[5]=5;
        exp_b[0]=0; exp_b[1]=0; exp_b[2]=1; exp_b[3]=2; exp_b[4]=2; exp_b[5]=3;
        exp_n = 6;
        run_join(16'h0011);
        check("Join Column-2");

        $display("\n=== %0d passed, %0d failed ===\n", pass_count, fail_count);
        $finish;
    end

    initial begin
        #(BIT_PERIOD * 6000);
        $display("TIMEOUT (jn=%0d)", jn);
        $finish;
    end

endmodule
