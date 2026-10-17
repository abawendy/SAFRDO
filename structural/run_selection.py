import serial
import time
import csv

# =============================================================================
# SAFRDO host script -- SELECTION (opcode 00)
# -----------------------------------------------------------------------------
# Standalone. Loads both CODED tables into BRAM, then asks the resident table
# (Table B) which rows have a chosen attribute equal to a chosen value.
# Selection substitutes an 8-bit constant for the streaming operand, so it can
# filter on ONE attribute per instruction (single-bit mask only).
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

def execute_vector_op(fpga, instruction_16bit):
    """Returns the 50-bit match vector (or None on timeout)."""
    fpga.write(b'\xEE')
    time.sleep(0.005)
    fpga.write(bytearray([(instruction_16bit >> 8) & 0xFF, instruction_16bit & 0xFF]))
    result_bytes = fpga.read(7)                        # 56 bits, top 6 are padding
    if len(result_bytes) != 7:
        print(f">>> ERROR: timed out. Got {len(result_bytes)} bytes instead of 7.")
        return None
    return int.from_bytes(result_bytes, byteorder='big') & ((1 << 50) - 1)

def decode_vector(vector, raw_rows, label):
    if vector is None:
        return
    hits = [i for i in range(len(raw_rows)) if (vector >> i) & 1]
    print(f">>> {label}: matched rows {hits}")
    for i in hits:
        print(f"      row {i}:  {', '.join(raw_rows[i])}")

# =============================================================================
# MAIN
# =============================================================================
if __name__ == "__main__":
    # ============ QUERY -- edit these two lines ============
    COLUMN = 'City'        # one of COL_NAMES: 'First', 'City', 'Phone', 'Status'
    VALUE  = 'Accra'       # the value to match in that column
    # ======================================================

    raw_a, raw_b = load_text_tables('table_A_text.csv', 'table_B_text.csv')
    dicts   = build_dictionaries(raw_a, raw_b)
    coded_a = encode_table(raw_a, dicts)
    coded_b = encode_table(raw_b, dicts)

    col = COL_NAMES.index(COLUMN)
    if VALUE not in dicts[col]:
        raise SystemExit(f"'{VALUE}' never appears in column '{COLUMN}' -- nothing to select.")
    code = dicts[col][VALUE]

    try:
        fpga = connect_to_fpga()
        time.sleep(1)
        fpga.write(b'\xFF')                            # reset memory pointers
        time.sleep(0.1)

        load_coded_table(fpga, coded_b, 'B')
        load_coded_table(fpga, coded_a, 'A')

        print(f"\n--- SELECTION: {COLUMN} == '{VALUE}' (code {code}) ---")
        vec = execute_vector_op(fpga, build_instruction(0, col_mask(col), code))
        decode_vector(vec, raw_b, f"B rows where {COLUMN}={VALUE}")

        fpga.close()

    except Exception as e:
        print(f"\nCRITICAL SCRIPT FAILURE: {e}")
