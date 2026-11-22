#!/usr/bin/env python3
"""
golden_model.py  --  Reference (golden) model for the systolic array accelerator

Number formats used by the RTL
    operands    : signed Q4.4   (8 bit,  4 fractional bits)
    accumulator : signed Q24.8  (32 bit, 8 fractional bits)
    requantised : signed Q4.4   (round-half-up + saturation, see rtl/requant.v)

The model is bit-exact with the hardware: C = A x B is computed with integer
MACs on the raw Q4.4 codes, exactly as the PEs do.

Running this script generates every vector file the testbenches need
(all files go to tests/vectors/):

  Phase I
    vectors.hex / vectors_count.hex          8 directed tests      (A,B,C)
  Phase II
    random_vectors.hex / random_count.hex    1000 random tests     (A,B,C)
    v2_vectors.hex / v2_count.hex            directed + 200 random (A,B,C,Q)
    requant_vectors.hex / requant_count.hex  requantiser input -> {sat,q}
    ws_vectors.hex                           16x4 * 4x4 for the WS array
    tiled8_vectors.hex, tiled12_vectors.hex  8x8 and 12x12 GEMMs (tiling)

Layouts (one hex word per line, $readmemh compatible)
    A,B,C   : per test N*N A words, N*N B words, N*N C words (row-major)
    A,B,C,Q : as above, then N*N words {sat, q[7:0]} (9 bit)

Pure Python 3 - no external packages needed.

Usage
    python3 golden_model.py              # writes all vector files
    python3 golden_model.py --seed 7     # different random seed
"""

import argparse
import os
import random

N = 4            # array dimension
DATA_W = 8       # operand width
ACC_W = 32       # accumulator width
FRAC_IN = 4      # Q4.4
FRAC_ACC = 2 * FRAC_IN   # Q24.8
OUT_W = 8        # requantised output width  (Q4.4)
OUT_FRAC = 4

# --------------------------------------------------------------------------
# Fixed-point helpers
# --------------------------------------------------------------------------
def sat(value, width):
    """Saturate a Python int to a signed 'width'-bit range."""
    lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
    return max(lo, min(hi, value))


def to_q44(x):
    """Real number -> raw signed Q4.4 code (round to nearest, saturate)."""
    return sat(int(round(x * (1 << FRAC_IN))), DATA_W)


def q44_to_real(code):
    return code / float(1 << FRAC_IN)


def acc_to_real(code):
    return code / float(1 << FRAC_ACC)


def requant(acc, in_frac=FRAC_ACC, out_w=OUT_W, out_frac=OUT_FRAC):
    """Bit-exact model of rtl/requant.v. Returns (q, saturated)."""
    sh = in_frac - out_frac
    v = (acc + (1 << (sh - 1))) >> sh if sh > 0 else acc   # >> is arithmetic in Python
    lo, hi = -(1 << (out_w - 1)), (1 << (out_w - 1)) - 1
    if v > hi:
        return hi, True
    if v < lo:
        return lo, True
    return v, False


def to_hex(value, width):
    """Two's complement hex string of a signed int."""
    mask = (1 << width) - 1
    return format(value & mask, "0{}x".format((width + 3) // 4))


# --------------------------------------------------------------------------
# Reference matrix multiply (bit-exact with the RTL)
# --------------------------------------------------------------------------
def matmul_raw(A, B):
    """A is M x K, B is K x P lists of raw Q4.4 codes. Returns raw Q24.8."""
    m, k, p = len(A), len(B), len(B[0])
    C = [[0] * p for _ in range(m)]
    for i in range(m):
        for j in range(p):
            acc = 0
            for t in range(k):
                acc += A[i][t] * B[t][j]
            assert -(1 << (ACC_W - 1)) <= acc < (1 << (ACC_W - 1)), "accumulator overflow"
            C[i][j] = acc
    return C


# --------------------------------------------------------------------------
# Test-case generators
# --------------------------------------------------------------------------
def identity(n):
    return [[1 if i == j else 0 for j in range(n)] for i in range(n)]


def directed_tests():
    tests = []
    A = [[i * N + j + 1 for j in range(N)] for i in range(N)]
    tests.append(("integer A x identity", A, identity(N)))

    B = [[(i + 1) * (j + 1) for j in range(N)] for i in range(N)]
    tests.append(("identity x integer B", identity(N), B))

    A = [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16]]
    B = [[16, 15, 14, 13], [12, 11, 10, 9], [8, 7, 6, 5], [4, 3, 2, 1]]
    tests.append(("positive integers", A, B))

    A = [[(i - j) * 3 for j in range(N)] for i in range(N)]
    B = [[(i + 1) * (j - 2) for j in range(N)] for i in range(N)]
    tests.append(("signed integers", A, B))

    Ar = [[1.5, -0.25, 2.0, 0.75],
          [-1.0, 3.25, 0.5, -2.5],
          [0.125, 0.0, -3.75, 1.0],
          [7.9375, -8.0, 0.0625, -0.5]]
    Br = [[2.25, 1.0, -0.5, 0.0],
          [0.5, -1.5, 2.0, 1.25],
          [-1.0, 0.25, 0.75, -2.0],
          [3.0, -0.125, 1.0, 0.5]]
    tests.append(("Q4.4 fractional", [[to_q44(x) for x in r] for r in Ar],
                  [[to_q44(x) for x in r] for r in Br]))

    A = [[-128] * N for _ in range(N)]
    tests.append(("extreme -8.0 x -8.0", A, [row[:] for row in A]))

    A = [[127] * N for _ in range(N)]
    B = [[-128] * N for _ in range(N)]
    tests.append(("+7.9375 x -8.0", A, B))

    Z = [[0] * N for _ in range(N)]
    tests.append(("zero x integer", Z, [[i - j for j in range(N)] for i in range(N)]))
    return tests


def rand_matrix(rng, rows, cols, lo=-128, hi=127):
    return [[rng.randint(lo, hi) for _ in range(cols)] for _ in range(rows)]


def random_tests(rng, count):
    """Mix of full-range and small-range (realistic, rarely saturating) tests."""
    tests = []
    for t in range(count):
        if t % 2 == 0:
            A, B = rand_matrix(rng, N, N), rand_matrix(rng, N, N)          # full range
        else:
            A, B = rand_matrix(rng, N, N, -24, 24), rand_matrix(rng, N, N, -24, 24)
        tests.append(("random %d" % t, A, B))
    return tests


# --------------------------------------------------------------------------
# File writers
# --------------------------------------------------------------------------
def write_count(path, n):
    with open(path, "w") as f:
        f.write(to_hex(n, 32) + "\n")


def write_abc(path, tests, with_q=False):
    with open(path, "w") as fh:
        fh.write("// generated by model/golden_model.py - per test A[16] B[16] C[16]%s\n"
                 % (" Q[16]" if with_q else ""))
        for idx, (name, A, B) in enumerate(tests):
            C = matmul_raw(A, B)
            fh.write("// test {} : {}\n".format(idx, name))
            for M, w in ((A, DATA_W), (B, DATA_W), (C, ACC_W)):
                for row in M:
                    fh.write(" ".join(to_hex(v, w) for v in row) + "\n")
            if with_q:
                for row in C:
                    words = []
                    for v in row:
                        q, s = requant(v)
                        words.append(to_hex((int(s) << 8) | (q & 0xFF), 12))
                    fh.write(" ".join(words) + "\n")


def fmt_matrix(M, conv=None, width=9):
    lines = []
    for row in M:
        if conv is None:
            lines.append("  " + " ".join("{:>{w}d}".format(v, w=width) for v in row))
        else:
            lines.append("  " + " ".join("{:>{w}.4f}".format(conv(v), w=width) for v in row))
    return "\n".join(lines)


def write_readable(path, tests):
    with open(path, "w") as ft:
        ft.write("Systolic array golden-model vectors (N={}, Q4.4 in, Q24.8 out)\n\n".format(N))
        for idx, (name, A, B) in enumerate(tests):
            C = matmul_raw(A, B)
            ft.write("=" * 70 + "\n")
            ft.write("test {} : {}\n".format(idx, name))
            ft.write("A (raw Q4.4 codes):\n" + fmt_matrix(A) + "\n")
            ft.write("A (real):\n" + fmt_matrix(A, q44_to_real) + "\n")
            ft.write("B (raw Q4.4 codes):\n" + fmt_matrix(B) + "\n")
            ft.write("B (real):\n" + fmt_matrix(B, q44_to_real) + "\n")
            ft.write("C expected (raw Q24.8):\n" + fmt_matrix(C) + "\n")
            ft.write("C expected (real):\n" + fmt_matrix(C, acc_to_real, 11) + "\n")
            ft.write("C requantised to Q4.4 (raw codes, * = saturated):\n")
            for row in C:
                cells = []
                for v in row:
                    q, s = requant(v)
                    cells.append("{:>6d}{}".format(q, "*" if s else " "))
                ft.write("  " + " ".join(cells) + "\n")
            ft.write("\n")


def write_requant_vectors(path_hex, path_cnt, rng):
    """Edge cases around every rounding / saturation boundary + random values."""
    vals = set()
    for base in (0, 8, 16, 2032, 2040, 2048, -2048, -2056, -2064, 100, -100):
        for d in range(-10, 11):
            vals.add(base + d)
    for v in (-(1 << 31), (1 << 31) - 1, 65536, -65536, 1 << 20, -(1 << 20)):
        vals.add(v)
    while len(vals) < 2000:
        if rng.random() < 0.5:
            vals.add(rng.randint(-4096, 4096))
        else:
            vals.add(rng.randint(-(1 << 31), (1 << 31) - 1))
    vals = sorted(vals)
    with open(path_hex, "w") as f:
        f.write("// requantiser vectors: din(32b) expected{sat,q}(9b)\n")
        for v in vals:
            q, s = requant(v)
            f.write("{} {}\n".format(to_hex(v, 32), to_hex((int(s) << 8) | (q & 0xFF), 12)))
    write_count(path_cnt, len(vals))
    return len(vals)


def write_gemm(path, A, B, name):
    """Generic GEMM file: A (MxK), B (KxP), C (MxP), row-major, no header."""
    C = matmul_raw(A, B)
    with open(path, "w") as f:
        f.write("// {}: A {}x{}, B {}x{}, C {}x{}\n".format(
            name, len(A), len(A[0]), len(B), len(B[0]), len(C), len(C[0])))
        for M, w in ((A, DATA_W), (B, DATA_W), (C, ACC_W)):
            for row in M:
                f.write(" ".join(to_hex(v, w) for v in row) + "\n")


# --------------------------------------------------------------------------
def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.join(here, "..", "tests", "vectors")
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=default_out, help="output directory")
    ap.add_argument("--seed", type=int, default=2026, help="random seed")
    ap.add_argument("--random", type=int, default=1000, help="number of random tests")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    o = lambda name: os.path.join(args.out, name)
    rng = random.Random(args.seed)

    # Phase I directed set (unchanged file names / layout)
    d = directed_tests()
    write_abc(o("vectors.hex"), d)
    write_count(o("vectors_count.hex"), len(d))
    write_readable(o("vectors_readable.txt"), d)

    # Phase II random regression
    r = random_tests(rng, args.random)
    write_abc(o("random_vectors.hex"), r)
    write_count(o("random_count.hex"), len(r))

    # Phase II top-level set with requantised outputs
    v2 = d + random_tests(rng, 200)
    write_abc(o("v2_vectors.hex"), v2, with_q=True)
    write_count(o("v2_count.hex"), len(v2))

    nreq = write_requant_vectors(o("requant_vectors.hex"), o("requant_count.hex"), rng)

    # Weight-stationary: tall A (16 x 4) times B (4 x 4)
    write_gemm(o("ws_vectors.hex"), rand_matrix(rng, 16, N), rand_matrix(rng, N, N), "ws 16x4x4")

    # Tiled GEMMs for the 4x4 array
    for s in (8, 12):
        write_gemm(o("tiled%d_vectors.hex" % s), rand_matrix(rng, s, s, -40, 40),
                   rand_matrix(rng, s, s, -40, 40), "tiled %dx%d" % (s, s))

    print("golden_model: wrote vectors to {}".format(os.path.normpath(args.out)))
    print("  directed {} | random {} | v2 {} | requant {} | ws 16x4x4 | tiled 8x8, 12x12"
          .format(len(d), len(r), len(v2), nreq))


if __name__ == "__main__":
    main()
