// =============================================================================
// File        : systolic_array_ws.v
// Project     : Systolic Array Matrix Multiplication Accelerator (CSA-222)
// Description : N x N weight-stationary systolic array.
//
//   PE(k,j) holds weight B[k][j]. Row k of the array receives column k of A
//   (A[i][k], skewed by k cycles) from the west. Partial sums enter the top
//   row as 0 and flow south; the bottom of column j produces
//   C[i][j] = sum_k A[i][k] * B[k][j]  at cycle i + j + N.
//
//   Ports (flattened)
//     w_north [j*DATA_W +: DATA_W]   weight load input of column j
//     a_west  [k*DATA_W +: DATA_W]   A operand for array row k
//     c_south [j*ACC_W  +: ACC_W]    result leaving column j
// =============================================================================
`timescale 1ns / 1ps

module systolic_array_ws #(
    parameter N      = 4,
    parameter DATA_W = 8,
    parameter ACC_W  = 32
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 en,
    input  wire                 load_w,
    input  wire [N*DATA_W-1:0]  w_north,
    input  wire [N*DATA_W-1:0]  a_west,
    output wire [N*ACC_W-1:0]   c_south
);

    wire [DATA_W-1:0] a_link [0:N*(N+1)-1];   // a_link[k*(N+1)+j] enters PE(k,j)
    wire [DATA_W-1:0] w_link [0:(N+1)*N-1];   // w_link[k*N+j]     enters PE(k,j)
    wire [ACC_W-1:0]  p_link [0:(N+1)*N-1];   // p_link[k*N+j]     enters PE(k,j)

    genvar k, j;
    generate
        for (k = 0; k < N; k = k + 1) begin : g_west
            assign a_link[k*(N+1)] = a_west[k*DATA_W +: DATA_W];
        end
        for (j = 0; j < N; j = j + 1) begin : g_north
            assign w_link[j] = w_north[j*DATA_W +: DATA_W];
            assign p_link[j] = {ACC_W{1'b0}};
            assign c_south[j*ACC_W +: ACC_W] = p_link[N*N + j];
        end
        for (k = 0; k < N; k = k + 1) begin : g_row
            for (j = 0; j < N; j = j + 1) begin : g_col
                pe_ws #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_pe (
                    .clk(clk), .rst_n(rst_n), .en(en), .load_w(load_w),
                    .w_in (w_link[k*N + j]),     .w_out(w_link[(k+1)*N + j]),
                    .a_in (a_link[k*(N+1) + j]), .a_out(a_link[k*(N+1) + j + 1]),
                    .p_in (p_link[k*N + j]),     .p_out(p_link[(k+1)*N + j])
                );
            end
        end
    endgenerate

endmodule
