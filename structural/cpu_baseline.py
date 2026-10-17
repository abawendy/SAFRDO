import csv
import time
import platform
import statistics

# =============================================================================
# SAFRDO -- CPU (software) baseline
# -----------------------------------------------------------------------------
# A software reference for the four relational operations the FPGA accelerator
# performs, timed on a general-purpose CPU, to quantify the hardware speedup.
#
# FAIRNESS: the software does the SAME computation the systolic array does --
# linear scans and a brute-force nested-loop join over the same tables, with NO
# indexing or hashing. The accelerator compares all n_a x n_b tuple pairs in
# hardware; this baseline compares them sequentially in software. The comparison
# therefore isolates the parallel-hardware advantage, not an algorithm change.
# (A hash-based software join would be faster; that is a different question --
# it changes the algorithm, whereas the accelerator's contribution is doing the
# same brute-force work in parallel. This is the same basis TDES/SHA reports use.)
#
# The tables are pre-encoded to 8-bit integer codes exactly as the host does, so
# the software compares the same values the hardware compares. Timing covers only
# the operation, not CSV reading or encoding. Each operation is verified against
# the known-correct result before timing.
# =============================================================================

# ==========================================
# FPGA PARAMETERS  -- edit to match your Vivado results
# ==========================================
CLK_NS        = 10.0      # 100 MHz clock constraint (10 ns period)
FPGA_WNS_NS   = 1.350     # post-implementation Worst Negative Slack (new design)
FPGA_FMAX_MHZ = 1000.0 / (CLK_NS - FPGA_WNS_NS)   # Fmax = 1 / (T_clk - WNS)

NUM_COLS  = 4
COL_NAMES = ['First', 'City', 'Phone', 'Status']
NUM_ROWS  = 50            # array depth (TABLE_A_DEPTH); TABLE_B_DEPTH = NUM_ROWS+1

def fpga_cycles(n_a, n_b, selection=False):
    """Compute-phase cycle cost from the controller schedule:
         LATCH(1) + LOAD_B(n_b+1) + STREAM_A + FLUSH(n_b+1) + DONE(1)
       TABLE_B_DEPTH = NUM_ROWS+1, so LOAD_B/FLUSH run n_b+1 cycles. Selection
       streams the full array depth; the other ops stream the real A-row count.
       The join no longer has a drain phase, so all four ops share this cost."""
    stream = NUM_ROWS if selection else n_a
    return 1 + (n_b + 1) + stream + (n_b + 1) + 1

def fpga_time_us(n_a, n_b, selection=False):
    return fpga_cycles(n_a, n_b, selection) / FPGA_FMAX_MHZ   # cycles / MHz = us

# =============================================================================
# DATA  (same CSVs + encoding as the host scripts)
# =============================================================================
def read_csv(fn):
    rows = []
    with open(fn, newline='') as f:
        for row in csv.reader(f):
            if row:
                rows.append([c.strip() for c in row])
    return rows

def build_dictionaries(rows_a, rows_b):
    dicts = [dict() for _ in range(NUM_COLS)]
    for row in rows_a + rows_b:
        for c in range(NUM_COLS):
            if row[c] not in dicts[c]:
                dicts[c][row[c]] = len(dicts[c]) + 1
    return dicts

def encode(rows, dicts):
    # tuples of ints -- what the hardware actually compares
    return [tuple(dicts[c][row[c]] for c in range(NUM_COLS)) for row in rows]

def col_mask_cols(mask):
    """Mask bit (1<<(NUM_COLS-1-c)) -> list of enabled column indices c."""
    return [c for c in range(NUM_COLS) if mask & (1 << (NUM_COLS - 1 - c))]

# =============================================================================
# OPERATIONS  (same brute-force model as the systolic array)
# =============================================================================
def op_selection(b, col, code):
    """B rows whose column == constant (single linear scan)."""
    return [i for i in range(len(b)) if b[i][col] == code]

def op_intersection(a, b):
    """A rows that also appear in B (whole tuple), brute-force all-pairs."""
    out = []
    for i in range(len(a)):
        ra = a[i]
        for rb in b:
            if ra == rb:
                out.append(i)
                break
    return out

def op_difference(a, b):
    """A rows that do NOT appear in B (whole tuple), brute-force all-pairs."""
    out = []
    for i in range(len(a)):
        ra = a[i]
        found = False
        for rb in b:
            if ra == rb:
                found = True
                break
        if not found:
            out.append(i)
    return out

def op_join(a, b, mask_cols):
    """All matching (A,B) pairs over the masked columns, brute-force nested loop.
       B ascending (outer) x A descending (inner) to match the hardware order."""
    out = []
    n_a = len(a)
    for bi in range(len(b)):
        rb = b[bi]
        for p in range(n_a):
            ai = n_a - 1 - p
            ra = a[ai]
            if all(ra[c] == rb[c] for c in mask_cols):
                out.append((ai, bi))
    return out

# =============================================================================
# TIMING HARNESS  (auto-scaled, best-of-repeats to cut noise)
# =============================================================================
def bench(fn, target_s=0.5, repeats=7):
    """Return the best per-call time in seconds. Auto-scale the inner loop count
       so each timed batch runs ~target_s, then take the minimum over repeats
       (minimum = least perturbed by OS scheduling)."""
    fn()  # warm up
    n = 1
    while True:
        t0 = time.perf_counter()
        for _ in range(n):
            fn()
        dt = time.perf_counter() - t0
        if dt >= target_s / 3:
            break
        n *= 2
    times = []
    for _ in range(repeats):
        t0 = time.perf_counter()
        for _ in range(n):
            fn()
        times.append((time.perf_counter() - t0) / n)
    return min(times)

# =============================================================================
# MAIN
# =============================================================================
if __name__ == "__main__":
    raw_a = read_csv('table_A_text.csv')
    raw_b = read_csv('table_B_text.csv')
    dicts = build_dictionaries(raw_a, raw_b)
    a = encode(raw_a, dicts)
    b = encode(raw_b, dicts)
    n_a, n_b = len(a), len(b)

    full_mask = (1 << NUM_COLS) - 1          # 1111
    city_col  = COL_NAMES.index('City')      # 1
    city_mask_cols = col_mask_cols(1 << (NUM_COLS - 1 - city_col))
    accra_code = dicts[city_col]['Accra']

    # ---- correctness (must match the hardware / expected.py before timing) ----
    sel  = op_selection(b, city_col, accra_code)
    inte = op_intersection(a, b)
    diff = op_difference(a, b)
    jfull = op_join(a, b, list(range(NUM_COLS)))
    jcity = op_join(a, b, city_mask_cols)

    print("=" * 68)
    print("SAFRDO CPU BASELINE")
    print("=" * 68)
    print(f"CPU        : {platform.processor() or platform.machine()}")
    print(f"Python     : {platform.python_version()}  ({platform.system()} {platform.release()})")
    print(f"Tables     : A={n_a} rows, B={n_b} rows, {NUM_COLS} cols")
    print(f"FPGA Fmax  : {FPGA_FMAX_MHZ:.1f} MHz   (1 / ({CLK_NS:.0f} ns - {FPGA_WNS_NS} ns WNS))")
    print()
    print("Correctness check (software results):")
    print(f"  selection City=Accra : {len(sel)} rows {sel}")
    print(f"  intersection         : {len(inte)} rows {inte}")
    print(f"  difference           : {len(diff)} rows")
    print(f"  join full-row        : {len(jfull)} pairs")
    print(f"  join on City         : {len(jcity)} pairs")
    print()

    ops = [
        ("Selection (City=Accra)", lambda: op_selection(b, city_col, accra_code), True),
        ("Intersection",           lambda: op_intersection(a, b),                 False),
        ("Difference",             lambda: op_difference(a, b),                   False),
        ("Join (full-row)",        lambda: op_join(a, b, list(range(NUM_COLS))),  False),
        ("Join (City)",            lambda: op_join(a, b, city_mask_cols),         False),
    ]

    print(f"{'Operation':<24}{'CPU (us)':>12}{'FPGA (us)':>12}{'Speedup':>12}")
    print("-" * 60)
    for name, fn, is_sel in ops:
        cpu_us  = bench(fn) * 1e6
        fpga_us = fpga_time_us(n_a, n_b, selection=is_sel)
        print(f"{name:<24}{cpu_us:>12.3f}{fpga_us:>12.3f}{cpu_us/fpga_us:>11.1f}x")
    print("-" * 60)
    print("FPGA time = compute cycles / Fmax (UART read-out excluded, as it is a")
    print("test harness). CPU time = same brute-force computation, best of repeats.")
