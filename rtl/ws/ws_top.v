// =============================================================================
// File        : ws_top.v
// Project     : Systolic Array Matrix Multiplication Accelerator (CSA-222)
// Description : Streaming weight-stationary accelerator (comparison design).
//
//   Computes C (M x N) = A (M x N) x B (N x N) for ANY number of rows M.
//
//   1. Weight load : for N cycles assert w_load with one row of B on w_row,
//                    LAST row first (B[N-1], B[N-2], ..., B[0]); the rows
//                    shift down so PE(k,j) ends up holding B[k][j].
//   2. Streaming   : every cycle with a_valid = 1 sends one row of A
//                    (lane k = A[i][k]). Rows can be sent back to back.
//   3. Results     : 2N-1 cycles later the matching row of C appears on
//                    c_row with c_valid = 1, in the same order.
//
//   Pipeline: input_skew (lane k delayed k) -> array -> output de-skew
//   (column j delayed N-1-j, reusing input_skew on reversed lanes) and a
//   (2N-1)-stage valid shift register. The array runs every cycle; invalid
//   rows are fed as zeros and their outputs are ignored.
//   Do not reload weights while rows are still in flight.
// =============================================================================
`timescale 1ns / 1ps

module ws_top #(
    parameter N      = 4,
    parameter DATA_W = 8,
    parameter ACC_W  = 32
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 w_load,
    input  wire [N*DATA_W-1:0]  w_row,
    input  wire                 a_valid,
    input  wire [N*DATA_W-1:0]  a_row,
    output wire                 c_valid,
    output wire [N*ACC_W-1:0]   c_row
);

    localparam LAT = 2*N - 1;

    wire [N*DATA_W-1:0] a_in = a_valid ? a_row : {(N*DATA_W){1'b0}};
    wire [N*DATA_W-1:0] a_west;
    wire [N*ACC_W-1:0]  c_south, c_south_rev, c_row_rev;

    input_skew #(.N(N), .DATA_W(DATA_W)) u_skew (
        .clk(clk), .rst_n(rst_n), .clear(1'b0), .en(1'b1), .din(a_in), .dout(a_west));

    systolic_array_ws #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) u_array (
        .clk(clk), .rst_n(rst_n), .en(1'b1), .load_w(w_load),
        .w_north(w_row), .a_west(a_west), .c_south(c_south));

    // de-skew: column j must be delayed by N-1-j -> reverse the lanes, use
    // input_skew (lane l delayed by l), reverse back
    genvar j;
    generate
        for (j = 0; j < N; j = j + 1) begin : g_rev
            assign c_south_rev[j*ACC_W +: ACC_W] = c_south[(N-1-j)*ACC_W +: ACC_W];
            assign c_row[j*ACC_W +: ACC_W]       = c_row_rev[(N-1-j)*ACC_W +: ACC_W];
        end
    endgenerate

    input_skew #(.N(N), .DATA_W(ACC_W)) u_deskew (
        .clk(clk), .rst_n(rst_n), .clear(1'b0), .en(1'b1), .din(c_south_rev), .dout(c_row_rev));

    // valid tracking
    reg [LAT-1:0] vpipe;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) vpipe <= {LAT{1'b0}};
        else        vpipe <= {vpipe[LAT-2:0], a_valid};
    end
    assign c_valid = vpipe[LAT-1];

endmodule
