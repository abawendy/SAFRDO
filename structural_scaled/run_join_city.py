import serial
import time
import csv

# =============================================================================
# SAFRDO host script -- EQUI-JOIN on CITY (opcode 01, mask 0100)
# -----------------------------------------------------------------------------
# Standalone. Loads both CODED tables into BRAM, then returns every pair of rows
# (one from A, one from B) that share the same City. This is run_join.py with the
# mask fixed to the City column.
#
# The join collector holds the full 50x50 match matrix; it is read out ROW BY ROW
# (one B-row's 50-bit match vector per read), and this script expands each vector
# into (A-index, B-index) pairs. There is NO 255-pair cap -- every match is
# reported (the City join returns 162 pairs on the sample tables).
#
# Text cells are turned into 8-bit codes on the laptop (one shared dictionary
# per column across BOTH tables); the hardware never sees a string.
# =============================================================================

# ==========================================
# HARDWARE CONFIGURATION
# ==========================================
COM_PORT  = 'COM8'      # Change this if Windows moves your board to a different port
BAUD_RATE = 115200      # Matches CLKS_PER_BIT = 868 at 100MHz

NUM_COLS  = 4                                   # Col3, Col2, Col1, Col0 (CSV left -> right)
COL_NAMES = ['First', 'City', 'Phone', 'Status']
NUM_ROWS  = 100                                 # SCALED build: hardware array depth (must match RTL)
NUM_TX_BYTES = (NUM_ROWS + 7) // 8              # bytes per row vector (7 @50)

def connect_to_fpga():
    print(f"Connecting to FPGA on {COM_PORT}...")
    return serial.Serial(COM_PORT, BAUD_RATE, timeout=2)

# =============================================================================
# HOST-SIDE TEXT <-> CODE LAYER
# =============================================================================
def load_text_tables(file_a, file_b):
    """Read both CSVs and return their RAW text rows (list of [c3, c2, c1, c0])."""
    def read_csv(filename):
        rows = []
        with open(filename, newline='') as f:
            for row in csv.reader(f):
                if not row:
                    continue
                rows.append([cell.strip() for cell in row])
        return rows
    return read_csv(file_a), read_csv(file_b)

def build_dictionaries(rows_a, rows_b):
    """One {text: code} dictionary per column, built across BOTH tables so the same
       string gets the same code everywhere. Codes start at 1 (0 = padding)."""
    dicts = [dict() for _ in range(NUM_COLS)]
    for row in rows_a + rows_b:
        for c in range(NUM_COLS):
            val = row[c]
            if val not in dicts[c]:
                code = len(dicts[c]) + 1
                if code > 255:
                    raise ValueError(
                        f"Column '{COL_NAMES[c]}' needs more than 255 distinct values "
                        f"-- widen the column past 8 bits before encoding it.")
                dicts[c][val] = code
    return dicts

def encode_table(rows, dicts):
    """Raw text rows -> integer-code rows the FPGA can compare."""
    return [[dicts[c][row[c]] for c in range(NUM_COLS)] for row in rows]

def col_mask(col_index):
    """CSV column index (0 = leftmost = Col3) -> hardware mask bit."""
    return 1 << (NUM_COLS - 1 - col_index)

# =============================================================================
# FPGA TRANSPORT
# =============================================================================
def load_coded_table(fpga, coded_rows, target):
    print(f"\n--- Loading Table {target} ({len(coded_rows)} coded rows) ---")
    command = b'\xAA' if target == 'A' else b'\xBB'   # 0xAA = Table A, 0xBB = Table B
    for idx, int_row in enumerate(coded_rows):
        print(f"Row {idx} codes: {int_row}")
        fpga.write(command)
        time.sleep(0.005)
        fpga.write(bytearray(int_row))                 # 4 code bytes, Col3 first
        time.sleep(0.005)

def build_instruction(opcode, mask, immediate):
    """Pack the 16-bit instruction: [15:8] immediate, [5:2] mask, [1:0] opcode."""
    return (immediate << 8) | (mask << 2) | opcode

def execute_join(fpga, instruction_16bit, n_a):
    """JOIN (01): the collector is read out ROW BY ROW. Wire format:
         byte 0            = number of B-rows that follow (num_b_rows)
         then per B-row b  = NUM_TX_BYTES bytes = that row's match vector, MSB first
       For row b, bit p (p < n_a) set means A_{n_a-1-p} matched B_b. We expand
       every set bit into an (a_idx, b_idx) pair. Emission order matches the
       host reference: b ascending (outer), p ascending (A descending, inner)."""
    fpga.write(b'\xEE')
    time.sleep(0.005)
    fpga.write(bytearray([(instruction_16bit >> 8) & 0xFF, instruction_16bit & 0xFF]))
    header = fpga.read(1)
    if len(header) != 1:
        print(">>> ERROR: no row-count header.")
        return []
    num_b = header[0]
    pairs = []
    for b in range(num_b):
        vec_bytes = fpga.read(NUM_TX_BYTES)
        if len(vec_bytes) != NUM_TX_BYTES:
            print(f">>> ERROR: row {b}: expected {NUM_TX_BYTES} bytes, got {len(vec_bytes)}.")
            return pairs
        vec = int.from_bytes(vec_bytes, byteorder='big') & ((1 << NUM_ROWS) - 1)
        for p in range(n_a):
            if (vec >> p) & 1:
                pairs.append((n_a - 1 - p, b))
    return pairs

def decode_join(pairs, raw_a, raw_b):
    print(f">>> {len(pairs)} matching pair(s):")
    for (a, b) in pairs:
        print(f"      A{a} <-> B{b} :  ({', '.join(raw_a[a])})  ==  ({', '.join(raw_b[b])})")

# =============================================================================
# MAIN
# =============================================================================
if __name__ == "__main__":
    # This script is hard-wired to join on the City column.
    col  = COL_NAMES.index('City')     # column 1
    MASK = col_mask(col)               # 0100

    raw_a, raw_b = load_text_tables('table_A_text.csv', 'table_B_text.csv')
    dicts   = build_dictionaries(raw_a, raw_b)
    coded_a = encode_table(raw_a, dicts)
    coded_b = encode_table(raw_b, dicts)

    try:
        fpga = connect_to_fpga()
        time.sleep(1)
        fpga.write(b'\xFF')                            # reset memory pointers
        time.sleep(0.1)

        load_coded_table(fpga, coded_b, 'B')
        load_coded_table(fpga, coded_a, 'A')

        print(f"\n--- JOIN on {COL_NAMES[col]}: A rows and B rows sharing a City (mask {MASK:04b}) ---")
        pairs = execute_join(fpga, build_instruction(1, MASK, 0), len(raw_a))
        decode_join(pairs, raw_a, raw_b)

        fpga.close()

    except Exception as e:
        print(f"\nCRITICAL SCRIPT FAILURE: {e}")
