import serial
import time
import csv

# ==========================================
# HARDWARE CONFIGURATION
# ==========================================
COM_PORT = 'COM8'      # Change this if Windows moves your board to a different port
BAUD_RATE = 115200     # Matches CLKS_PER_BIT = 868 at 100MHz

def connect_to_fpga():
    print(f"Connecting to FPGA on {COM_PORT}...")
    # 2-second timeout prevents the script from hanging forever if the board is off
    return serial.Serial(COM_PORT, BAUD_RATE, timeout=2)

def load_table_from_csv(fpga, filename, target):
    print(f"\n--- Loading {filename} into Table {target} ---")
    # 0xAA for Table A, 0xBB for Table B
    command = b'\xAA' if target == 'A' else b'\xBB'
    
    try:
        with open(filename, mode='r') as file:
            reader = csv.reader(file)
            for idx, row in enumerate(reader):
                # Parse string rows into integer arrays [Col3, Col2, Col1, Col0]
                int_row = [int(val) for val in row]
                print(f"Row {idx} loaded: {int_row}")
                
                # 1. Send the Write Command
                fpga.write(command)
                time.sleep(0.005) # Tiny buffer to let state machine shift to LOAD_MEM
                
                # 2. Send the 4 data bytes (Big Endian sequence)
                fpga.write(bytearray(int_row))
                time.sleep(0.005)
    except FileNotFoundError:
        print(f"Error: Could not find {filename} in the current directory.")

def build_instruction(opcode, mask, immediate):
    """
    Packs the 16-bit instruction exactly as the SystemVerilog controller expects it.
    Format: [15:8] Immediate, [7:6] Padding, [5:2] Mask, [1:0] Opcode
    """
    # Shift immediate up to the top 8 bits
    inst = (immediate << 8)
    
    # Shift mask into bits 5 through 2
    inst = inst | (mask << 2)
    
    # Opcode sits perfectly at bits 1 and 0
    inst = inst | opcode
    
    return inst

def execute_instruction(fpga, instruction_16bit):
    print(f"\n--- Executing Hardware Instruction: {hex(instruction_16bit)} ---")
    
    # 1. Send the Execute Command
    fpga.write(b'\xEE')
    time.sleep(0.005)
    
    # 2. Slice the 16-bit instruction into two bytes and send (High then Low)
    high_byte = (instruction_16bit >> 8) & 0xFF
    low_byte = instruction_16bit & 0xFF
    fpga.write(bytearray([high_byte, low_byte]))
    
    print("Waiting for hardware accelerator...")
    
    # 3. Read 7 bytes (56 bits) back from the FPGA
    result_bytes = fpga.read(7)
    
    if len(result_bytes) == 7:
        # Convert the raw byte array into a single large integer
        result_int = int.from_bytes(result_bytes, byteorder='big')

        # Mask out the top 6 padded zeros to isolate your exact 50-bit vector
        final_vector = result_int & ((1 << 50) - 1)
        print(f">>> SUCCESS! Hardware Result Vector: {bin(final_vector)}")
    else:
        print(f">>> ERROR: Hardware timed out. Received {len(result_bytes)} bytes instead of 7.")

def execute_join(fpga, instruction_16bit):
    """
    JOIN (opcode 01): returns the actual matching PAIRS (A_row, B_row), not a
    one-sided bitmask. The hardware streams back a variable-length pair list:
        byte 0        = number of pairs
        then per pair = A-index byte, B-index byte
    """
    print(f"\n--- Executing JOIN: {hex(instruction_16bit)} ---")

    # 1. Send the Execute Command + the 2 instruction bytes (High then Low)
    fpga.write(b'\xEE')
    time.sleep(0.005)
    high_byte = (instruction_16bit >> 8) & 0xFF
    low_byte  = instruction_16bit & 0xFF
    fpga.write(bytearray([high_byte, low_byte]))

    print("Waiting for hardware accelerator...")

    # 2. Read the header byte = how many pairs the hardware found
    header = fpga.read(1)
    if len(header) != 1:
        print(">>> ERROR: Hardware timed out (no pair-count header).")
        return
    count = header[0]

    # 3. Read 2 bytes per pair and decode
    body = fpga.read(2 * count)
    if len(body) != 2 * count:
        print(f">>> ERROR: Expected {2*count} pair bytes, got {len(body)}.")
        return

    print(f">>> SUCCESS! {count} matching pair(s):")
    for p in range(count):
        a_idx = body[2 * p]
        b_idx = body[2 * p + 1]
        print(f"      A{a_idx}  <->  B{b_idx}")

# ==========================================
# MAIN EXECUTION THREAD
# ==========================================
if __name__ == "__main__":
    try:
        fpga = connect_to_fpga()
        time.sleep(1) # Give the serial port a moment to physically open
        
        # 1. Reset hardware memory pointers (Command 0xFF)
        fpga.write(b'\xFF')
        time.sleep(0.1)
        
        # 2. Beam the Databases into BRAM
        load_table_from_csv(fpga, 'table_B.csv', 'B')
        load_table_from_csv(fpga, 'table_A.csv', 'A')
        
        print("\n--- RUNNING DIAGNOSTIC SWEEP ON ROW 0 ---")
        print("Expected Vector output for Row 0 match: 0b1 (or 0b11... if empty rows collide)")
        
        # Test 1: Selection (Opcode 0), Col 3 (Mask 1000 = 8), Target 10
        print("Test 1 (Col 3): Looking for 10...")
        execute_instruction(fpga, build_instruction(0, 8, 10))
        
        # Test 2: Selection (Opcode 0), Col 2 (Mask 0100 = 4), Target 255
        print("Test 2 (Col 2): Looking for 255...")
        execute_instruction(fpga, build_instruction(0, 4, 255))
        
        # Test 3: Selection (Opcode 0), Col 1 (Mask 0010 = 2), Target 30
        print("Test 3 (Col 1): Looking for 30...")
        execute_instruction(fpga, build_instruction(0, 2, 30))
        
        # Test 4: Selection (Opcode 0), Col 0 (Mask 0001 = 1), Target 40
        print("Test 4 (Col 0): Looking for 40...")
        execute_instruction(fpga, build_instruction(0, 1, 40))

        # --- INTERSECTION (Opcode 2) ---
        # Streams Table A against Table B and returns a PER-A-ROW bitmask:
        # bit i = 1 means row i of Table A matches some row of Table B.
        # The immediate is unused here; the mask selects which columns must match.
        print("\n--- INTERSECTION: which rows of Table A are also in Table B? ---")

        # TRUE set intersection (mask 1111 = 15): all 4 columns must match, so a row
        # of A counts only if the COMPLETE tuple exists in B.
        print("Intersection (true / full-row, all columns)...")
        execute_instruction(fpga, build_instruction(2, 15, 0))

        # PARTIAL match (mask 0100 = 4): only Column 2 is compared. This is NOT a true
        # intersection -- it reports which A rows merely share a Column-2 value with B
        # (a single-column / semi-join style match).
        print("Partial match (Column 2 only -- not a full intersection)...")
        execute_instruction(fpga, build_instruction(2, 4, 0))

        # --- JOIN (Opcode 1) ---
        # Returns the actual matching PAIRS (A_row, B_row). The hardware bounds the
        # join to the real loaded rows, so empty zero-slots never produce phantoms.
        print("\n--- JOIN: which rows of A pair with which rows of B? ---")

        # FULL-COLUMN join (mask 1111 = 15): all 4 columns must match -> true join
        # on the complete tuple. Expected pairs: A0<->B0, A2<->B1, A4<->B2, A5<->B3.
        print("Join (full row, all columns)...")
        execute_join(fpga, build_instruction(1, 15, 0))

        # SINGLE-COLUMN join (mask 0100 = 4): pair rows that share a Column-2 value.
        print("Join (Column 2 only)...")
        execute_join(fpga, build_instruction(1, 4, 0))

        fpga.close()
        
    except Exception as e:
        print(f"\nCRITICAL SCRIPT FAILURE: {e}")