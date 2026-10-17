import csv

# =============================================================================
# SAFRDO scaled build -- test-data generator (NUM_ROWS = 100)
# -----------------------------------------------------------------------------
# Produces everything the 100-row design needs to be exercised and checked:
#   * table_A_text.csv / table_B_text.csv   -- 100 text rows each (host input)
#   * A_codes.mem / B_codes.mem             -- 100 x 32-bit hex words ($readmemh)
#   * expected.txt                          -- hand-checkable expected results
#
# The data is planted so the expected results are clean:
#   * A[i] == B[i] for i in 0..DUP-1  (DUP identical, distinct tuples)  -> those
#     are the ONLY whole-tuple matches, so intersection = join(full) = DUP.
#   * every other row gets a globally-unique Phone, so no accidental full match.
#   * Cities are drawn from a small pool (incl. 'Accra') so City-join and the
#     City=Accra selection have meaningful, countable results.
#
# Word packing matches the hardware: [31:24]=First(Col3) [23:16]=City(Col2)
# [15:8]=Phone(Col1) [7:0]=Status(Col0), i.e. CSV column c -> mask bit 1<<(3-c).
# =============================================================================

NUM_ROWS = 100
NUM_COLS = 4
COL_NAMES = ['First', 'City', 'Phone', 'Status']
DUP = 10                       # planted identical rows (A[i]==B[i], i<DUP)

CITIES = ['Accra','Kumasi','Tema','Takoradi','Tamale','CapeCoast','Ho','Obuasi',
          'Wa','Bolgatanga','Koforidua','Sunyani','Techiman','Tarkwa','Winneba','Nkawkaw']
FIRSTS = ['John','Sophia','Kwame','Ama','Yaw','Kofi','Akua','Kojo','Abena','Kwesi',
          'Adwoa','Yaa','Efua','Nana','Esi','Kwabena','Afia','Fiifi','Araba','Ekow',
          'Maame','Kwaku','Akosua','Mensah']
STATUS = ['Active','Inactive']

def planted(i):
    return [FIRSTS[i % len(FIRSTS)], CITIES[i % len(CITIES)],
            f'024{1000000+i}', STATUS[i % 2]]

rows_a, rows_b = [], []
for i in range(NUM_ROWS):
    if i < DUP:
        rows_a.append(planted(i))
        rows_b.append(planted(i))          # identical tuple in both tables
    else:
        rows_a.append([FIRSTS[i % len(FIRSTS)],       CITIES[i % len(CITIES)],
                       f'055A{i:04d}', STATUS[i % 2]])
        rows_b.append([FIRSTS[(i + 5) % len(FIRSTS)], CITIES[(i + 3) % len(CITIES)],
                       f'055B{i:04d}', STATUS[(i + 1) % 2]])

# ---- shared per-column encoding (codes start at 1; 0 = padding) -------------
dicts = [dict() for _ in range(NUM_COLS)]
for row in rows_a + rows_b:
    for c in range(NUM_COLS):
        if row[c] not in dicts[c]:
            code = len(dicts[c]) + 1
            if code > 255:
                raise ValueError(f"column {COL_NAMES[c]} exceeds 255 codes")
            dicts[c][row[c]] = code

def encode(rows):
    return [[dicts[c][row[c]] for c in range(NUM_COLS)] for row in rows]

ca, cb = encode(rows_a), encode(rows_b)

def word(code_row):   # First<<24 | City<<16 | Phone<<8 | Status
    return (code_row[0] << 24) | (code_row[1] << 16) | (code_row[2] << 8) | code_row[3]

def write_csv(fn, rows):
    with open(fn, 'w', newline='') as f:
        w = csv.writer(f)
        for r in rows:
            w.writerow(r)

def write_mem(fn, coded):
    with open(fn, 'w') as f:
        for r in coded:
            f.write(f"{word(r):08x}\n")

write_csv('table_A_text.csv', rows_a)
write_csv('table_B_text.csv', rows_b)
write_mem('A_codes.mem', ca)
write_mem('B_codes.mem', cb)

# ---- expected results (software reference) ----------------------------------
def matches(ra, rb, mask_cols):
    return all(ra[c] == rb[c] for c in mask_cols)

accra = dicts[1]['Accra']
sel = [i for i in range(NUM_ROWS) if cb[i][1] == accra]           # B City=Accra
inter = [i for i in range(NUM_ROWS) if any(ca[i] == cb[j] for j in range(NUM_ROWS))]
diff = [i for i in range(NUM_ROWS) if ca[i] not in cb]
jfull = [(i, j) for j in range(NUM_ROWS) for i in range(NUM_ROWS) if ca[i] == cb[j]]
jcity = [(i, j) for j in range(NUM_ROWS) for i in range(NUM_ROWS) if matches(ca[i], cb[j], [1])]

sel_vec = 0
for i in sel:
    sel_vec |= (1 << i)

with open('expected.txt', 'w') as f:
    f.write(f"NUM_ROWS      {NUM_ROWS}\n")
    f.write(f"accra_code    {accra}\n")
    f.write(f"selection_rows {sel}\n")
    f.write(f"selection_vec  {sel_vec:0{(NUM_ROWS+3)//4}x}\n")
    f.write(f"intersection  {len(inter)} {inter}\n")
    f.write(f"difference    {len(diff)}\n")
    f.write(f"join_full     {len(jfull)}\n")
    f.write(f"join_city     {len(jcity)}\n")

print("=== generated 100-row data ===")
print(f"  selection City=Accra (B) : {len(sel)} rows -> {sel}")
print(f"  selection vector (hex)   : {sel_vec:0{(NUM_ROWS+3)//4}x}")
print(f"  intersection             : {len(inter)} rows -> {inter}")
print(f"  difference               : {len(diff)} rows")
print(f"  join full-row            : {len(jfull)} pairs")
print(f"  join on City             : {len(jcity)} pairs")
print(f"  accra_code               : {accra}")
print("  wrote: table_A_text.csv table_B_text.csv A_codes.mem B_codes.mem expected.txt")
