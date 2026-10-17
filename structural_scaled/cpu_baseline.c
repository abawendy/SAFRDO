/* =============================================================================
 * SAFRDO -- CPU (software) baseline, C version
 * -----------------------------------------------------------------------------
 * Compiled-C reference for the four relational operations the FPGA accelerator
 * performs, timed on a general-purpose CPU. This is the conservative companion
 * to cpu_baseline.py: identical operations, identical brute-force model (linear
 * scans + nested-loop join, NO indexing/hashing), same tables -- but compiled,
 * so the speedup figure is not inflated by interpreter overhead.
 *
 * FAIRNESS: the software does the SAME work the systolic array does. The array
 * compares all n_a x n_b tuple pairs in parallel hardware; this compares them
 * sequentially in software. The ratio isolates the parallel-hardware advantage.
 *
 * Build (MinGW / gcc):   gcc -O2 -o cpu_baseline cpu_baseline.c
 * Run (from structural/): ./cpu_baseline
 * (Needs table_A_text.csv and table_B_text.csv in the working directory.)
 * ============================================================================= */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#if defined(__GNUC__) && (defined(__x86_64__) || defined(__i386__))
#include <cpuid.h>
#endif

#define NUM_COLS 4
#define MAX_ROWS 256
#define MAX_STR  64
#define MAX_VALS 256   /* distinct values per column (codes 1..255) */

/* ---- FPGA parameters (edit to match your Vivado results) ------------------ */
static const double CLK_NS      = 10.0;    /* 100 MHz constraint */
static const double FPGA_WNS_NS = 0.320;   /* post-implementation WNS (new design) */
/* Fmax = 1 / (T_clk - WNS), in MHz */
#define FPGA_FMAX_MHZ (1000.0 / (CLK_NS - FPGA_WNS_NS))

/* Compute-phase cycles: LATCH(1)+LOAD_B(n_b+1)+STREAM_A+FLUSH(n_b+1)+DONE(1).
 * TABLE_B_DEPTH = NUM_ROWS+1; selection streams the full depth, others n_a.
 * The join has no drain phase, so all four ops share this cost. */
static int    g_num_rows = 100;             /* array depth (TABLE_A_DEPTH) */
static int fpga_cycles(int n_a, int n_b, int selection) {
    int stream = selection ? g_num_rows : n_a;
    return 1 + (n_b + 1) + stream + (n_b + 1) + 1;
}
static double fpga_time_us(int n_a, int n_b, int selection) {
    return (double)fpga_cycles(n_a, n_b, selection) / FPGA_FMAX_MHZ; /* cycles/MHz = us */
}

/* ---- encoded tables (tuples of 8-bit-range integer codes) ----------------- */
static int A[MAX_ROWS][NUM_COLS], B[MAX_ROWS][NUM_COLS];
static int na = 0, nb = 0;

/* per-column string->code dictionaries, shared across A and B */
static char g_dict[NUM_COLS][MAX_VALS][MAX_STR];
static int  g_dict_n[NUM_COLS] = {0};

static int intern(int col, const char *s) {
    for (int i = 0; i < g_dict_n[col]; i++)
        if (strcmp(g_dict[col][i], s) == 0) return i + 1;      /* codes start at 1 */
    int idx = g_dict_n[col]++;
    strncpy(g_dict[col][idx], s, MAX_STR - 1);
    g_dict[col][idx][MAX_STR - 1] = '\0';
    return idx + 1;
}

static void trim(char *s) {
    char *p = s;
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
    size_t n = strlen(s);
    while (n > 0 && (s[n-1]==' '||s[n-1]=='\t'||s[n-1]=='\r'||s[n-1]=='\n')) s[--n] = '\0';
}

/* read a CSV of 4 comma-separated text fields per line, encode into dst */
static int load_csv(const char *fn, int dst[][NUM_COLS]) {
    FILE *f = fopen(fn, "r");
    if (!f) { fprintf(stderr, "cannot open %s\n", fn); exit(1); }
    char line[512];
    int rows = 0;
    while (fgets(line, sizeof line, f)) {
        trim(line);
        if (line[0] == '\0') continue;
        char *save = NULL, *tok = strtok(line, ",");
        int c = 0;
        while (tok && c < NUM_COLS) {
            char field[MAX_STR];
            strncpy(field, tok, MAX_STR - 1); field[MAX_STR-1] = '\0';
            trim(field);
            dst[rows][c] = intern(c, field);
            c++;
            tok = strtok(NULL, ",");
        }
        if (c == NUM_COLS) rows++;
    }
    fclose(f);
    return rows;
}

static inline int tuple_eq(const int *x, const int *y) {
    return x[0]==y[0] && x[1]==y[1] && x[2]==y[2] && x[3]==y[3];
}

/* ---- operations (checksum return so the optimiser can't delete the work) --- */
static long op_selection(int col, int code) {       /* B rows where col == code */
    long s = 0;
    for (int i = 0; i < nb; i++) if (B[i][col] == code) s += i + 1;
    return s;
}
static long op_intersection(void) {                 /* A rows present in B */
    long s = 0;
    for (int i = 0; i < na; i++)
        for (int j = 0; j < nb; j++)
            if (tuple_eq(A[i], B[j])) { s += i + 1; break; }
    return s;
}
static long op_difference(void) {                   /* A rows NOT in B */
    long s = 0;
    for (int i = 0; i < na; i++) {
        int found = 0;
        for (int j = 0; j < nb; j++) if (tuple_eq(A[i], B[j])) { found = 1; break; }
        if (!found) s += i + 1;
    }
    return s;
}
/* join over the columns whose bit is set in mask[]; B outer, A descending inner */
static long op_join(const int *mcols, int ncols) {
    long s = 0;
    for (int bi = 0; bi < nb; bi++)
        for (int p = 0; p < na; p++) {
            int ai = na - 1 - p, ok = 1;
            for (int k = 0; k < ncols; k++) if (A[ai][mcols[k]] != B[bi][mcols[k]]) { ok = 0; break; }
            if (ok) s += (long)ai * 31 + bi + 1;
        }
    return s;
}

/* query parameters resolved in main() */
static int g_city_col, g_accra_code;
static const int MASK_CITY[1]       = {1};       /* join key: City (col 1)            */
static const int MASK_CITY_STAT[2]  = {1, 3};    /* join key: City + Status (cols 1,3) */

static long b_selection(void)   { return op_selection(g_city_col, g_accra_code); }
static long b_intersection(void){ return op_intersection(); }         /* whole tuple */
static long b_difference(void)  { return op_difference(); }           /* whole tuple */
static long b_join_1col(void)   { return op_join(MASK_CITY, 1); }
static long b_join_2col(void)   { return op_join(MASK_CITY_STAT, 2); }

/* ---- counts for the correctness check (must match the hardware) ----------- */
static int count_selection(int col, int code) { int n=0; for(int i=0;i<nb;i++) if(B[i][col]==code) n++; return n; }
static int count_intersection(void){ int n=0; for(int i=0;i<na;i++) for(int j=0;j<nb;j++) if(tuple_eq(A[i],B[j])){n++;break;} return n; }
static int count_difference(void){ int n=0; for(int i=0;i<na;i++){int f=0;for(int j=0;j<nb;j++) if(tuple_eq(A[i],B[j])){f=1;break;} if(!f)n++;} return n; }
static int count_join(const int*mc,int nc){ int n=0; for(int bi=0;bi<nb;bi++) for(int ai=0;ai<na;ai++){int ok=1;for(int k=0;k<nc;k++) if(A[ai][mc[k]]!=B[bi][mc[k]]){ok=0;break;} if(ok)n++;} return n; }

/* ---- timing harness: auto-scale, then RUNS independent timings ------------- */
#define RUNS 5                                      /* runs averaged, like the TDES benchmark */
static void bench(long (*fn)(void), double us_out[RUNS]) {
    volatile long sink = 0;
    sink += fn();                                   /* warm up */
    long n = 1;
    for (;;) {                                      /* auto-scale batch so a timing is measurable */
        clock_t t0 = clock();
        for (long i = 0; i < n; i++) sink += fn();
        double dt = (double)(clock() - t0) / CLOCKS_PER_SEC;
        if (dt >= 0.50 || n > 100000000L) break;    /* long batch -> stable per-run number */
        n *= 2;
    }
    for (int r = 0; r < RUNS; r++) {                /* one timing per run */
        clock_t t0 = clock();
        for (long i = 0; i < n; i++) sink += fn();
        us_out[r] = ((double)(clock() - t0) / CLOCKS_PER_SEC) / (double)n * 1e6; /* us/call */
    }
    (void)sink;
}

static void cpu_brand(char *buf, size_t n) {
#if defined(__GNUC__) && (defined(__x86_64__) || defined(__i386__))
    unsigned int r[4]; char tmp[49]; char *p = tmp;
    for (unsigned leaf = 0x80000002u; leaf <= 0x80000004u; leaf++) {
        if (!__get_cpuid(leaf, &r[0], &r[1], &r[2], &r[3])) { strncpy(buf,"(unknown)",n); return; }
        memcpy(p, r, 16); p += 16;
    }
    *p = '\0';
    strncpy(buf, tmp, n); buf[n-1] = '\0';
#else
    strncpy(buf, "(record manually)", n); buf[n-1] = '\0';
#endif
}

int main(void) {
    nb = load_csv("table_B_text.csv", B);
    na = load_csv("table_A_text.csv", A);

    /* City column index and the code for "Accra" */
    g_city_col = 1;
    g_accra_code = 0;
    for (int i = 0; i < g_dict_n[g_city_col]; i++)
        if (strcmp(g_dict[g_city_col][i], "Accra") == 0) { g_accra_code = i + 1; break; }

    char brand[64]; cpu_brand(brand, sizeof brand);

    printf("====================================================================\n");
    printf("SAFRDO CPU BASELINE (compiled C)\n");
    printf("====================================================================\n");
    printf("CPU        : %s\n", brand);
    printf("Tables     : A=%d rows, B=%d rows, %d cols\n", na, nb, NUM_COLS);
    printf("FPGA Fmax  : %.1f MHz   (1 / (%.0f ns - %.3f ns WNS))\n\n",
           FPGA_FMAX_MHZ, CLK_NS, FPGA_WNS_NS);

    printf("Correctness check (software results):\n");
    printf("  selection City=Accra : %d rows\n", count_selection(g_city_col, g_accra_code));
    printf("  intersection         : %d rows\n", count_intersection());
    printf("  difference           : %d rows\n", count_difference());
    printf("  join 1-col (City)    : %d pairs\n", count_join(MASK_CITY, 1));
    printf("  join 2-col (City+St) : %d pairs\n\n", count_join(MASK_CITY_STAT, 2));

    struct { const char *name; long (*fn)(void); int sel; } ops[] = {
        {"Selection (City=Accra)",    b_selection,    1},
        {"Intersection",              b_intersection, 0},
        {"Difference",                b_difference,   0},
        {"Join (1 col: City)",        b_join_1col,    0},
        {"Join (2 col: City+Status)", b_join_2col,    0},
    };

    double cpu_avg[5];

    /* ---- per-run CPU times (each operation timed RUNS times) ---- */
    printf("Per-run CPU time (us), %d runs:\n", RUNS);
    printf("%-28s", "Operation");
    for (int r = 0; r < RUNS; r++) printf("   run%d", r + 1);
    printf("       avg\n");
    for (int i = 0; i < 5; i++) {
        double t[RUNS], sum = 0;
        bench(ops[i].fn, t);
        for (int r = 0; r < RUNS; r++) sum += t[r];
        cpu_avg[i] = sum / RUNS;
        printf("%-28s", ops[i].name);
        for (int r = 0; r < RUNS; r++) printf("%7.2f", t[r]);
        printf("%10.4f\n", cpu_avg[i]);
    }

    /* ---- summary: average CPU vs FPGA ---- */
    printf("\nSummary (CPU = average of %d runs):\n", RUNS);
    printf("%-28s%12s%12s%12s\n", "Operation", "CPU (us)", "FPGA (us)", "Speedup");
    printf("------------------------------------------------------------\n");
    for (int i = 0; i < 5; i++) {
        double fpga_us = fpga_time_us(na, nb, ops[i].sel);
        printf("%-28s%12.4f%12.3f%11.1fx\n", ops[i].name, cpu_avg[i], fpga_us, cpu_avg[i] / fpga_us);
    }
    printf("------------------------------------------------------------\n");
    printf("FPGA time = compute cycles / Fmax (UART read-out excluded, a test\n");
    printf("harness). CPU time = same brute-force computation, averaged over %d runs.\n", RUNS);
    return 0;
}
