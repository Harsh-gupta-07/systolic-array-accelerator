// =============================================================================
// File        : systolic_top_v2.v
// Project     : Systolic Array Matrix Multiplication Accelerator (CSA-222)
// Description : Phase II top level: streaming-capable accelerator.
//
//   Improvements over systolic_top (Phase I):
//     * Row-wide host interface: one row of A/B written (N elements) and one
//       row of C read (N results) per cycle instead of one element.
//     * Ping-pong input buffers (matrix_buffer_pp): load the next operands
//       while the current product is computed.
//     * Result buffer: accumulators are copied on 'done', so results can be
//       read while the next product is already running.
//     * Back-to-back starts and accumulate mode (systolic_controller_v2).
//     * Output requantisation to Q4.4 with saturation flags (requant).
//     * Hardware performance counters (perf_counters).
//     * Optional pipelined MAC (MUL_PIPE) and registered buffer outputs
//       (BUF_REG) for a higher clock frequency (+1 cycle latency each).
//
//   +---------------+  a/b_vec  +--------+      +----------------+  c_flat  +--------+
//   | ping-pong A/B |---------->| skew   |----->| N x N PE array |--------->| result |--> rd_data (Q24.8)
//   |  buffers      |           | A & B  |      | (OS, MUL_PIPE) |          | buffer |--> requant --> rd_q, rd_sat
//   +---------------+           +--------+      +----------------+          +--------+
//          ^ wr_*         swap, feed, k | clear, en          capture  |
//          |                    +-----------------------------------+
//          |                    | systolic_controller_v2            |--> busy, done
//      host interface           +-----------------------------------+--> perf_counters
// =============================================================================
`timescale 1ns / 1ps

module systolic_top_v2 #(
    parameter N        = 4,
    parameter DATA_W   = 8,
    parameter ACC_W    = 32,
    parameter MUL_PIPE = 0,
    parameter BUF_REG  = 0,     // 1 = registered buffer outputs (timing)
    parameter OUT_W    = 8,     // requantised output width   (Q4.4)
    parameter OUT_FRAC = 4,     // requantised fractional bits
    parameter KW       = (N > 1) ? $clog2(N) : 1
) (
    input  wire                     clk,
    input  wire                     rst_n,
    // control / status
    input  wire                     start,
    input  wire                     acc_mode,
    output wire                     busy,
    output wire                     done,
    // operand write (row-wide, shadow bank)
    input  wire                     wr_en,
    input  wire                     wr_sel,     // 0 = A, 1 = B
    input  wire [KW-1:0]            wr_row,
    input  wire [N*DATA_W-1:0]      wr_data,
    // result read (row-wide, from result buffer)
    input  wire [KW-1:0]            rd_row,
    output wire [N*ACC_W-1:0]       rd_data,    // raw Q24.8, lane c = C[row][c]
    output wire [N*OUT_W-1:0]       rd_q,       // requantised Q4.4
    output wire [N-1:0]             rd_sat,     // saturation flag per lane
    // performance counters
    input  wire                     perf_clr,
    input  wire [1:0]               perf_sel,
    output wire [31:0]              perf_data
);

    wire          clear, en, feed, swap, capture;
    wire [KW-1:0] k_idx;
    wire          active_bank;

    wire [N*DATA_W-1:0]  a_vec, b_vec, a_west, b_north;
    wire [N*N*ACC_W-1:0] c_flat;
    reg  [N*N*ACC_W-1:0] result;

    systolic_controller_v2 #(.N(N), .MUL_PIPE(MUL_PIPE), .BUF_REG(BUF_REG), .KW(KW)) u_ctrl (
        .clk(clk), .rst_n(rst_n), .start(start), .acc_mode(acc_mode),
        .clear(clear), .en(en), .feed(feed), .k_idx(k_idx),
        .swap(swap), .capture(capture), .busy(busy), .done(done)
    );

    matrix_buffer_pp #(.N(N), .DATA_W(DATA_W), .OUT_REG(BUF_REG), .KW(KW)) u_buf (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_row(wr_row), .wr_data(wr_data),
        .swap(swap), .active(active_bank),
        .feed(feed), .k_idx(k_idx), .a_vec(a_vec), .b_vec(b_vec)
    );

    input_skew #(.N(N), .DATA_W(DATA_W)) u_skew_a (
        .clk(clk), .rst_n(rst_n), .clear(clear), .en(en), .din(a_vec), .dout(a_west));
    input_skew #(.N(N), .DATA_W(DATA_W)) u_skew_b (
        .clk(clk), .rst_n(rst_n), .clear(clear), .en(en), .din(b_vec), .dout(b_north));

    systolic_array #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W), .MUL_PIPE(MUL_PIPE)) u_array (
        .clk(clk), .rst_n(rst_n), .clear(clear), .en(en),
        .a_west(a_west), .b_north(b_north), .c_flat(c_flat)
    );

    // ---------------- result buffer ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       result <= {(N*N*ACC_W){1'b0}};
        else if (capture) result <= c_flat;
    end

    assign rd_data = result[rd_row*N*ACC_W +: N*ACC_W];

    // ---------------- requantisation, one unit per lane ----------------
    genvar c;
    generate
        for (c = 0; c < N; c = c + 1) begin : g_rq
            requant #(.IN_W(ACC_W), .IN_FRAC(2*(DATA_W/2)), .OUT_W(OUT_W), .OUT_FRAC(OUT_FRAC)) u_rq (
                .din  (rd_data[c*ACC_W +: ACC_W]),
                .dout (rd_q[c*OUT_W +: OUT_W]),
                .sat  (rd_sat[c])
            );
        end
    endgenerate

    // ---------------- performance counters ----------------
    perf_counters u_perf (
        .clk(clk), .rst_n(rst_n), .perf_clr(perf_clr),
        .busy(busy), .en(en), .done(done),
        .sel(perf_sel), .data(perf_data)
    );

endmodule
