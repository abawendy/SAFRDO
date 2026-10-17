import serial
import time
import csv

# =============================================================================
# SAFRDO host script -- TEXT EDITION
# -----------------------------------------------------------------------------
# The accelerator only ever tests EQUALITY (comparator.sv: a_in == b_in), so it
# never needs the real strings. This script turns every text cell (names, cities,
# phone numbers, status) into a small 8-bit CODE on the laptop -- one shared
# dictionary PER COLUMN spanning BOTH tables -- ships the codes to BRAM exactly
# like the numeric version, then decodes the FPGA's row-indices back into the
# original readable rows. The hardware is completely unchanged.
# =============================================================================

# ==========================================
# HARDWARE CONFIGURATION
# ==========================================
COM_PORT  = 'COM8'      # Change this if Windows moves your board to a different port
BAUD_RATE = 115200      # Matches CLKS_PER_BIT = 868 at 100MHz

NUM_COLS  = 4                                   # Col3, Col2, Col1, Col0 (CSV left -> right)
COL_NAMES = ['First', 'City', 'Phone', 'Status']
NUM_ROWS  = 50                                  # hardware array depth (must match RTL)
NUM_TX_BYTES = (NUM_ROWS + 7) // 8              # bytes per row vector (7 @50)

def connect_to_fpga():
    print(f"Connecting to FPGA on {COM_PORT}...")
    # 2-second timeout prevents the script from hanging forever if the board is off
    return serial.Serial(COM_PORT, BAUD_RATE, timeout=2)

# =============================================================================
# HOST-SIDE TEXT <-> CODE LAYER  (everything below the FPGA never sees a string)
# =============================================================================
def load_text_tables(file_a, file_b):
    """Read both CSVs and return their RAW text rows (list of [c3, c2, c1, c0])."""
    def read_csv(filename):
        rows = []
        with open(filename, newline='') as f:
            for row in csv.reader(f):
                if not row:
                    continue                      # skip blank lines
                rows.append([cell.strip() for cell in row])
        return rows
    return read_csv(file_a), read_csv(file_b)

def build_dictionaries(rows_a, rows_b):
    """One {text: code} dictionary per column, built across BOTH tables so the same
       string gets the same code everywhere (otherwise a join could never match).
       Codes start at 1 -- 0 stays reserved as the empty/padding sentinel, matching
       the zero-padded BRAM rows. Errors if a column needs more than 255 codes."""
    dicts = [dict() for _ in range(NUM_COLS)]
    for row in rows_a + rows_b:
        for c in range(NUM_COLS):
            val = row[c]
            if val not in dicts[c]:
                code = len(dicts[c]) + 1          # next code, starting at 1
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
# FPGA TRANSPORT  (identical bytes to the numeric host script)
# =============================================================================
def load_coded_table(fpga, coded_rows, target):
    print(f"\n--- Loading Table {target} ({len(coded_rows)} coded rows) ---")
    command = b'\xAA' if target == 'A' else b'\xBB'   # 0xAA = Table A, 0xBB = Table B
    for idx, int_row in enumerate(coded_rows):
        print(f"Row {idx} codes: {int_row}")
        fpga.write(command)
        time.sleep(0.005)                              # let the FSM shift to LOAD_MEM
        fpga.write(bytearray(int_row))                 # 4 code bytes, Col3 first
        time.sleep(0.005)

def build_instruction(opcode, mask, immediate):
    """Pack the 16-bit instruction: [15:8] immediate, [5:2] mask, [1:0] opcode."""
    return (immediate << 8) | (mask << 2) | opcode

def execute_vector_op(fpga, instruction_16bit):
    """Selection (00) / intersection (10) / difference (11): returns the 50-bit
       match vector (or None on timeout)."""
    fpga.write(b'\xEE')
    time.sleep(0.005)
    fpga.write(bytearray([(instruction_16bit >> 8) & 0xFF, instruction_16bit & 0xFF]))
    result_bytes = fpga.read(7)                        # 56 bits, top 6 are padding
    if len(result_bytes) != 7:
        print(f">>> ERROR: timed out. Got {len(result_bytes)} bytes instead of 7.")
        return None
    return int.from_bytes(result_bytes, byteorder='big') & ((1 << 50) - 1)

def execute_join(fpga, instruction_16bit, n_a):
    """JOIN (01): the collector is read out ROW BY ROW. Wire format:
         byte 0            = number of B-rows that follow (num_b_rows)
         then per B-row b  = NUM_TX_BYTES bytes = that row's match vector, MSB first
       For row b, bit p (p < n_a) set means A_{n_a-1-p} matched B_b. Every set bit
       becomes an (a_idx, b_idx) pair. (Old format was byte0=pair count then A,B
       per pair -- superseded by the row-wise readout.)"""
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

# =============================================================================
# DECODE  (turn the FPGA's indices back into readable rows)
# =============================================================================
def decode_vector(vector, raw_rows, label):
    if vector is None:
        return
    hits = [i for i in range(len(raw_rows)) if (vector >> i) & 1]
    print(f">>> {label}: {len(hits)} match(es)")
    for i in hits:
        print(f"      row {i}:  {', '.join(raw_rows[i])}")

def decode_join(pairs, raw_a, raw_b, max_show=20):
    print(f">>> {len(pairs)} matching pair(s):")
    for (a, b) in pairs[:max_show]:
        print(f"      A{a} <-> B{b} :  ({', '.join(raw_a[a])})  ==  ({', '.join(raw_b[b])})")
    if len(pairs) > max_show:
        print(f"      ... ({len(pairs) - max_show} more)")

# =============================================================================
# MAIN
# =============================================================================
if __name__ == "__main__":
    # ---- Host side: read text, build ONE dictionary per column, encode ----
    raw_a, raw_b = load_text_tables('table_A_text.csv', 'table_B_text.csv')
    dicts   = build_dictionaries(raw_a, raw_b)
    coded_a = encode_table(raw_a, dicts)
    coded_b = encode_table(raw_b, dicts)

    print("=== Per-column dictionaries (text -> 8-bit code, shared across A & B) ===")
    for c in range(NUM_COLS):
        print(f"  {COL_NAMES[c]:7}: {dicts[c]}")

    try:
        fpga = connect_to_fpga()
        time.sleep(1)                                  # let the serial port open
        fpga.write(b'\xFF')                            # reset memory pointers
        time.sleep(0.1)

        # Beam the CODED tables into BRAM
        load_coded_table(fpga, coded_b, 'B')
        load_coded_table(fpga, coded_a, 'A')

        # --- SELECTION: which resident (B) rows have City == "Accra"? ---
        col, want = 1, 'Accra'
        code = dicts[col][want]
        print(f"\n--- SELECTION: {COL_NAMES[col]} == '{want}' (code {code}) ---")
        vec = execute_vector_op(fpga, build_instruction(0, col_mask(col), code))
        decode_vector(vec, raw_b, f"B rows where {COL_NAMES[col]}={want}")

        # --- INTERSECTION: which A rows fully exist in B (all 4 columns)? ---
        print("\n--- INTERSECTION: A rows that also appear in B (whole tuple) ---")
        vec = execute_vector_op(fpga, build_instruction(2, 15, 0))
        decode_vector(vec, raw_a, "A rows present in B")

        # --- DIFFERENCE: which A rows are NOT in B (all 4 columns)? ---
        print("\n--- DIFFERENCE: A rows that do NOT appear in B (whole tuple) ---")
        vec = execute_vector_op(fpga, build_instruction(3, 15, 0))
        decode_vector(vec, raw_a, "A rows absent from B")

        # --- JOIN (1 column): rows sharing the same City ---
        col = 1
        print(f"\n--- JOIN (1 column): rows sharing the same {COL_NAMES[col]} ---")
        pairs = execute_join(fpga, build_instruction(1, col_mask(col), 0), len(raw_a))
        decode_join(pairs, raw_a, raw_b)

        # --- JOIN (2 columns): rows sharing the same City AND Status ---
        c1, c2 = 1, 3
        two_col_mask = col_mask(c1) | col_mask(c2)
        print(f"\n--- JOIN (2 columns): rows sharing the same {COL_NAMES[c1]} AND {COL_NAMES[c2]} ---")
        pairs = execute_join(fpga, build_instruction(1, two_col_mask, 0), len(raw_a))
        decode_join(pairs, raw_a, raw_b)

        fpga.close()

    except Exception as e:
        print(f"\nCRITICAL SCRIPT FAILURE: {e}")
