// =============================================================================
// File        : seq_matmul.v
// Project     : Systolic Array Matrix Multiplication Accelerator (CSA-222)
// Description : Sequential baseline: matrix multiply with ONE MAC unit.
//
//   This is how a simple processor (or a minimal accelerator) computes
//   C = A x B: a triple loop, one multiply-accumulate per clock cycle.
//
//       for i in 0..N-1
//         for j in 0..N-1
//           for k in 0..N-1
//             acc = (k == 0 ? 0 : acc) + A[i][k] * B[k][j]
//           C[i][j] = acc
//
//   Exactly N^3 cycles per product (64 for N = 4): the first MAC of each
//   element loads the product instead of adding, and the last MAC writes
//   C[i][j] directly, so there are no bubble cycles.
//
//   The host interface is identical to systolic_top (Phase I), so the same
//   testbench (tb_systolic_top.v with +define+DUT_SEQ) verifies both designs.
// =============================================================================
`timescale 1ns / 1ps

module seq_matmul #(
    parameter N      = 4,
    parameter DATA_W = 8,
    parameter ACC_W  = 32,
    parameter AW     = (N*N > 1) ? $clog2(N*N) : 1,
    parameter KW     = (N   > 1) ? $clog2(N)   : 1
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    output wire                     busy,
    output wire                     done,
    input  wire                     wr_en,
    input  wire                     wr_sel,
    input  wire [AW-1:0]            wr_addr,
    input  wire [DATA_W-1:0]        wr_data,
    input  wire [AW-1:0]            rd_addr,
    output wire signed [ACC_W-1:0]  rd_data
);

    localparam [1:0] S_IDLE = 2'd0, S_RUN = 2'd1, S_DONE = 2'd2;

    // Operand and result storage as small memories (mapped to LUT-RAM by
    // synthesis), like the register file / scratchpad of a simple CPU.
    reg [DATA_W-1:0] a_mem [0:N*N-1];
    reg [DATA_W-1:0] b_mem [0:N*N-1];
    reg [ACC_W-1:0]  c_mem [0:N*N-1];

    reg [1:0]              state;
    reg [KW-1:0]           i, j, k;
    reg signed [ACC_W-1:0] acc;

    // ---------------- operand storage (same write port as Phase I) ----------
    always @(posedge clk) begin
        if (wr_en && wr_sel == 1'b0) a_mem[wr_addr] <= wr_data;
        if (wr_en && wr_sel == 1'b1) b_mem[wr_addr] <= wr_data;
    end

    // ---------------- single MAC datapath ----------------
    wire [AW-1:0] a_addr = i*N + k;
    wire [AW-1:0] b_addr = k*N + j;
    wire [AW-1:0] c_addr = i*N + j;

    wire signed [DATA_W-1:0]   a_op = a_mem[a_addr];
    wire signed [DATA_W-1:0]   b_op = b_mem[b_addr];
    wire signed [2*DATA_W-1:0] prod = a_op * b_op;
    wire signed [ACC_W-1:0]    prod_ext = {{(ACC_W-2*DATA_W){prod[2*DATA_W-1]}}, prod};
    wire signed [ACC_W-1:0]    sum = (k == 0) ? prod_ext : acc + prod_ext;

    wire last_k = (k == N-1);
    wire last_j = (j == N-1);
    wire last_i = (i == N-1);

    // result write: C[i][j] is written by the last MAC of its dot product
    always @(posedge clk) begin
        if (state == S_RUN && last_k)
            c_mem[c_addr] <= sum;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            i <= 0; j <= 0; k <= 0;
            acc   <= 0;
        end else begin
            case (state)
                S_IDLE: if (start) begin
                    state <= S_RUN;
                    i <= 0; j <= 0; k <= 0;
                end
                S_RUN: begin
                    acc <= sum;
                    if (last_k) begin
                        k <= 0;
                        if (last_j) begin
                            j <= 0;
                            if (last_i) state <= S_DONE;
                            else        i <= i + 1'b1;
                        end else
                            j <= j + 1'b1;
                    end else
                        k <= k + 1'b1;
                end
                S_DONE: state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end

    assign busy    = (state == S_RUN);
    assign done    = (state == S_DONE);
    assign rd_data = c_mem[rd_addr];

endmodule
