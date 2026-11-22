// =============================================================================
// File        : systolic_array.v
// Project     : Systolic Array Matrix Multiplication Accelerator (CSA-222)
// Owner       : Member 3
// Description : N x N output-stationary systolic array built from PEs.
//
//                 b_north[0]   b_north[1]  ...  b_north[N-1]
//                     |            |                |
//   a_west[0]   --> PE(0,0) --> PE(0,1) --> ... --> PE(0,N-1)
//                     |            |                |
//   a_west[1]   --> PE(1,0) --> PE(1,1) --> ... --> PE(1,N-1)
//                     :            :                :
//   a_west[N-1] --> PE(N-1,0) -->  ...      --> PE(N-1,N-1)
//
//   * Row i of A enters on a_west[i] and travels east.
//   * Column j of B enters on b_north[j] and travels south.
//   * PE(i,j) accumulates C[i][j] = sum_k A[i][k] * B[k][j].
//   * Inputs must be skewed (row i delayed by i cycles, column j by j cycles)
//     so that A[i][k] and B[k][j] meet inside PE(i,j) on the same cycle.
//     The skewing is done outside this module by input_skew.v.
//
// Port packing (flattened buses, Verilog-2005 compatible)
//   a_west [i*DATA_W +: DATA_W]          -> row i input
//   b_north[j*DATA_W +: DATA_W]          -> column j input
//   c_flat [(i*N + j)*ACC_W +: ACC_W]    -> C[i][j]
// =============================================================================
`timescale 1ns / 1ps

module systolic_array #(
    parameter N        = 4,
    parameter DATA_W   = 8,
    parameter ACC_W    = 32,
    parameter MUL_PIPE = 0
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear,
    input  wire                    en,
    input  wire [N*DATA_W-1:0]     a_west,
    input  wire [N*DATA_W-1:0]     b_north,
    output wire [N*N*ACC_W-1:0]    c_flat
);

    // Horizontal links: a_link[i*(N+1) + j] is the A operand entering PE(i,j);
    // a_link[i*(N+1) + N] is the (unused) east edge output of row i.
    wire [DATA_W-1:0] a_link [0:N*(N+1)-1];

    // Vertical links: b_link[i*N + j] is the B operand entering PE(i,j);
    // b_link[N*N + j] is the (unused) south edge output of column j.
    wire [DATA_W-1:0] b_link [0:(N+1)*N-1];

    genvar i, j;
    generate
        // ---- boundary connections ----
        for (i = 0; i < N; i = i + 1) begin : g_west_edge
            assign a_link[i*(N+1)] = a_west[i*DATA_W +: DATA_W];
        end
        for (j = 0; j < N; j = j + 1) begin : g_north_edge
            assign b_link[j] = b_north[j*DATA_W +: DATA_W];
        end

        // ---- PE grid ----
        for (i = 0; i < N; i = i + 1) begin : g_row
            for (j = 0; j < N; j = j + 1) begin : g_col
                pe #(
                    .DATA_W   (DATA_W),
                    .ACC_W    (ACC_W),
                    .MUL_PIPE (MUL_PIPE)
                ) u_pe (
                    .clk     (clk),
                    .rst_n   (rst_n),
                    .clear   (clear),
                    .en      (en),
                    .a_in    (a_link[i*(N+1) + j]),
                    .b_in    (b_link[i*N + j]),
                    .a_out   (a_link[i*(N+1) + j + 1]),
                    .b_out   (b_link[(i+1)*N + j]),
                    .acc_out (c_flat[(i*N + j)*ACC_W +: ACC_W])
                );
            end
        end
    endgenerate

endmodule
