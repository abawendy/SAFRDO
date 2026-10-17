`timescale 1ns / 1ps

module safrdo_uart_bridge #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10,
    parameter NUM_ROWS   = 100   // SCALED build: array height / Table B capacity (was 50)
)(
    input  logic clk_100mhz,
    input  logic reset_btn,
    
    // Physical pins to the USB cable
    input  logic uart_rx_pin,
    output logic uart_tx_pin
);

    // ==========================================
    // 1. INTERNAL WIRES
    // ==========================================
    // UART RX Wires
    logic [7:0] rx_byte;
    logic       rx_ready;
    
    // UART TX Wires
    logic [7:0] tx_byte;
    logic       tx_start;
    logic       tx_busy;

    // Safrdo Top Wires (The Brain)
    logic        cpu_start, done_signal;
    logic [15:0] cpu_instruction;
    
    logic        cpu_we_A, cpu_we_B;
    logic [ADDR_WIDTH-1:0] cpu_addr_A, cpu_addr_B;
    logic [DATA_WIDTH-1:0] cpu_data_A, cpu_data_B;
    
    logic [NUM_ROWS-1:0] final_data_out;
    logic [NUM_ROWS-1:0] final_valid_out; // Handled internally, not sent over UART

    // JOIN read-out cursor (declared here so the instantiation below can wire it)
    localparam int IDX_W = $clog2(NUM_ROWS);       // one row index (6 @50)
    logic [IDX_W-1:0]  join_row_ptr;               // which B-row is being read

    // ==========================================
    // 2. INSTANTIATIONS
    // ==========================================
    // The Ears
    uart_rx #(.CLKS_PER_BIT(868)) U_RX (
        .clk(clk_100mhz), .reset(reset_btn), .rx(uart_rx_pin),
        .rx_data(rx_byte), .rx_ready(rx_ready)
    );

    // The Mouth
    uart_tx #(.CLKS_PER_BIT(868)) U_TX (
        .clk(clk_100mhz), .reset(reset_btn), .tx_start(tx_start),
        .tx_data(tx_byte), .tx_busy(tx_busy), .tx(uart_tx_pin)
    );

    // The Brain (Your exact hardware design)
    safrdo_top #(
        .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .NUM_ROWS(NUM_ROWS)
    ) U_ACCEL (
        .clk(clk_100mhz), .rst(reset_btn),
        .cpu_start(cpu_start), .done_signal(done_signal), .cpu_instruction(cpu_instruction),
        // Load pointers double as the real row counts that bound the JOIN
        .num_a_rows(cpu_addr_A), .num_b_rows(cpu_addr_B),
        // Bridge walks the collector's B-rows during JOIN read-out
        .join_row_sel(join_row_ptr),
        .cpu_we_A(cpu_we_A), .cpu_addr_A(cpu_addr_A), .cpu_data_A(cpu_data_A),
        .cpu_we_B(cpu_we_B), .cpu_addr_B(cpu_addr_B), .cpu_data_B(cpu_data_B),
        .final_data_out(final_data_out), .final_valid_out(final_valid_out)
    );

    // ==========================================
    // 3. THE BRIDGE STATE MACHINE
    // ==========================================
    typedef enum logic [3:0] {
        IDLE, LOAD_MEM, GET_INSTR, WAIT_EXEC, SEND_RESULT,
        SEND_JOIN_HDR, SEND_JOIN_LOAD, SEND_JOIN_BODY
    } state_t;
    state_t state;

    // Packing Registers
    logic [31:0] shift_reg_32;
    logic        target_bram; // 0 = BRAM A, 1 = BRAM B

    // Result accumulator: catches the transient row-match vector as it
    // streams out, gated by final_valid_out (same logic proven in tb_safrdo_top).
    logic [NUM_ROWS-1:0] result_reg;

    // Serial write pointer for intersection/difference: the scalar t_i emerges one
    // bit per streamed A row, so we pack each into the next bit position.
    logic [$clog2(NUM_ROWS+1)-1:0] row_ptr;

    // Safety backstop so a missing pulse can never hang the serial capture.
    logic [15:0] exec_timeout;

    // ----- JOIN read-out (row-wise, UART-paced) -------------------------------
    // After a join, the collector holds the full match matrix. The bridge walks
    // the B-rows: for each row it reads that row's 50-bit match vector off
    // final_data_out (router in join mode) and streams it out as NUM_TX_BYTES
    // bytes. The host expands each vector into (A_idx, B_idx) pairs. No pair
    // buffer, no 255-pair cap -- every match is reported.
    // (join_row_ptr / IDX_W are declared up top so the instantiation can wire them.)
    
    // ==========================================
    // DYNAMIC UART SIZING MATH
    // ==========================================
    // Calculate how many 8-bit bytes are needed to fit NUM_ROWS
    localparam NUM_TX_BYTES  = (NUM_ROWS + 7) / 8; 
    
    
    // Explicitly define the width so Questa doesn't have to guess
    localparam TOTAL_TX_BITS = (NUM_TX_BYTES * 8);
    
    logic [TOTAL_TX_BITS-1:0] tx_shift_reg; 
    logic [15:0]              byte_counter; // Expanded to handle large arrays safely

    always_ff @(posedge clk_100mhz) begin
        if (reset_btn) begin
            state        <= IDLE;
            cpu_addr_A   <= '0;
            cpu_addr_B   <= '0;
            cpu_we_A     <= 1'b0;
            cpu_we_B     <= 1'b0;
            cpu_start    <= 1'b0;
            tx_start     <= 1'b0;
            byte_counter <= '0;
            join_row_ptr <= '0;
        end else begin
            // Default pulldowns (ensure these only spike for 1 cycle)
            cpu_we_A  <= 1'b0;
            cpu_we_B  <= 1'b0;
            cpu_start <= 1'b0;
            tx_start  <= 1'b0;

            // Advance the write pointer the cycle AFTER the write fires, so the
            // synchronous BRAM write lands at the CURRENT address (not addr+1).
            if (cpu_we_A) cpu_addr_A <= cpu_addr_A + 1'b1;
            if (cpu_we_B) cpu_addr_B <= cpu_addr_B + 1'b1;

            case (state)
                // ---------------------------------------------------
                // STATE 1: Wait for a Command from the Laptop
                // ---------------------------------------------------
                IDLE: begin
                    byte_counter <= '0;
                    if (rx_ready) begin
                        if (rx_byte == 8'hAA) begin
                            target_bram <= 1'b0;
                            state <= LOAD_MEM;
                        end else if (rx_byte == 8'hBB) begin
                            target_bram <= 1'b1;
                            state <= LOAD_MEM;
                        end else if (rx_byte == 8'hEE) begin
                            state <= GET_INSTR;
                        end else if (rx_byte == 8'hFF) begin
                            cpu_addr_A <= '0;
                            cpu_addr_B <= '0;
                        end
                    end
                end

                // ---------------------------------------------------
                // STATE 2: Pack 4 Bytes & Write to BRAM
                // ---------------------------------------------------
                LOAD_MEM: begin
                    if (rx_ready) begin
                        shift_reg_32 <= {shift_reg_32[23:0], rx_byte};
                        
                        if (byte_counter == 3) begin
                            if (target_bram == 1'b0) begin
                                cpu_data_A <= {shift_reg_32[23:0], rx_byte};
                                cpu_we_A   <= 1'b1;
                                // pointer advances in the default section, post-write
                            end else begin
                                cpu_data_B <= {shift_reg_32[23:0], rx_byte};
                                cpu_we_B   <= 1'b1;
                                // pointer advances in the default section, post-write
                            end
                            state <= IDLE;
                        end else begin
                            byte_counter <= byte_counter + 1'b1;
                        end
                    end
                end

                // ---------------------------------------------------
                // STATE 3: Pack 2 Bytes & Start the Math
                // ---------------------------------------------------
                GET_INSTR: begin
                    if (rx_ready) begin
                        if (byte_counter == 0) begin
                            cpu_instruction[15:8] <= rx_byte;
                            byte_counter <= 1;
                        end else begin
                            cpu_instruction[7:0] <= rx_byte;
                            cpu_start <= 1'b1;
                            result_reg   <= '0; // clear before this execution
                            row_ptr      <= '0; // reset serial pointer too
                            join_row_ptr <= '0; // reset join read pointer too
                            exec_timeout <= '0;
                            state <= WAIT_EXEC;
                        end
                    end
                end

                // ---------------------------------------------------
                // STATE 4: Let the Hardware work
                // ---------------------------------------------------
                WAIT_EXEC: begin
                    exec_timeout <= exec_timeout + 1'b1;

                    if (cpu_instruction[1:0] == 2'b00) begin
                        // SELECTION (vector): each row's match arrives in its own bit
                        // position, valid at a staggered time. OR-accumulate spatially,
                        // and latch on done_signal.
                        result_reg <= result_reg | (final_data_out & final_valid_out);
                        if (done_signal) begin
                            tx_shift_reg <= TOTAL_TX_BITS'(result_reg | (final_data_out & final_valid_out));
                            byte_counter <= '0;
                            state <= SEND_RESULT;
                        end
                    end else if (cpu_instruction[1:0] == 2'b01) begin
                        // JOIN: nothing to capture here -- the collector already
                        // holds the full match matrix. When the core signals done,
                        // start walking the B-rows and reading them out (row-wise).
                        if (done_signal) begin
                            join_row_ptr <= '0;
                            state <= SEND_JOIN_HDR;
                        end
                    end else begin
                        // INTERSECTION/DIFFERENCE (scalar t_i): one bit per streamed A
                        // row, serial. The datapath now aligns the valid strobe with
                        // the settled t_i, so we just pack on each valid pulse (A row 0
                        // -> bit 0). Keep capturing past done_signal until drained.
                        if (final_valid_out[0] && row_ptr < NUM_ROWS) begin
                            result_reg[row_ptr] <= final_data_out[0];
                            row_ptr <= row_ptr + 1'b1;
                        end
                        // Send once all rows are captured (or the safety timeout trips).
                        if (row_ptr == NUM_ROWS || exec_timeout > 16'd400) begin
                            tx_shift_reg <= TOTAL_TX_BITS'(result_reg);
                            byte_counter <= '0;
                            state <= SEND_RESULT;
                        end
                    end
                end

                // ---------------------------------------------------
                // STATE 5: Send dynamically sized Bytes back to Laptop
                // ---------------------------------------------------
                SEND_RESULT: begin
                    if (!tx_busy && !tx_start) begin
                        
                        // Use a fixed width for the slice to satisfy Questa
                        // We always send the top 8 bits of the current register state
                        tx_byte  <= tx_shift_reg[TOTAL_TX_BITS-1 -: 8];
                        tx_start <= 1'b1;
                        
                        if (byte_counter == (NUM_TX_BYTES - 1)) begin
                            state <= IDLE;
                        end else begin
                            // Use a generate-like shift logic that Questa prefers
                            tx_shift_reg <= tx_shift_reg << 8;
                            byte_counter <= byte_counter + 1'b1;
                        end
                    end
                end

                // ---------------------------------------------------
                // STATE 6a: JOIN read-out header
                //   Send one byte = number of B-rows (how many vectors follow).
                //   join_row_ptr is already 0, so the collector is presenting
                //   B-row 0 on final_data_out; SEND_JOIN_LOAD latches it next.
                // ---------------------------------------------------
                SEND_JOIN_HDR: begin
                    if (!tx_busy && !tx_start) begin
                        tx_byte  <= cpu_addr_B[7:0];   // num_b_rows
                        tx_start <= 1'b1;
                        if (cpu_addr_B == '0) state <= IDLE;          // nothing loaded
                        else                  state <= SEND_JOIN_LOAD;
                    end
                end

                // ---------------------------------------------------
                // STATE 6b: Latch the current B-row's 50-bit match vector
                //   join_row_ptr has been stable for a cycle, so final_data_out
                //   (= collector sr[join_row_ptr]) has settled. Grab it, then
                //   stream it out byte-by-byte in SEND_JOIN_BODY.
                // ---------------------------------------------------
                SEND_JOIN_LOAD: begin
                    tx_shift_reg <= TOTAL_TX_BITS'(final_data_out);
                    byte_counter <= '0;
                    state        <= SEND_JOIN_BODY;
                end

                // ---------------------------------------------------
                // STATE 6c: Stream NUM_TX_BYTES bytes of the current row vector,
                //   MSB first (same shaping as SEND_RESULT). After the last byte,
                //   advance to the next B-row or finish.
                // ---------------------------------------------------
                SEND_JOIN_BODY: begin
                    if (!tx_busy && !tx_start) begin
                        tx_byte  <= tx_shift_reg[TOTAL_TX_BITS-1 -: 8];
                        tx_start <= 1'b1;

                        if (byte_counter == (NUM_TX_BYTES - 1)) begin
                            // Whole row sent
                            if (join_row_ptr == IDX_W'(cpu_addr_B - 1'b1)) begin
                                state <= IDLE;                     // last B-row done
                            end else begin
                                join_row_ptr <= join_row_ptr + 1'b1; // next B-row...
                                state        <= SEND_JOIN_LOAD;      // ...settle + latch
                            end
                        end else begin
                            tx_shift_reg <= tx_shift_reg << 8;
                            byte_counter <= byte_counter + 1'b1;
                        end
                    end
                end
            endcase
        end
    end

endmodule