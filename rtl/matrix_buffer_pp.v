// =============================================================================
// File        : matrix_buffer_pp.v
// Project     : Systolic Array Matrix Multiplication Accelerator (CSA-222)
// Description : Double-buffered (ping-pong) input buffers, Phase II.
//
//   Two banks for A and two for B. At any time one bank is ACTIVE (read by
//   the array) and the other is the SHADOW (written by the host). The host
//   can therefore load the next pair of matrices while the current product
//   is being computed. 'swap' (pulsed by the controller when a new run is
//   accepted) flips the roles of the banks.
//
//   Write side  : one whole ROW per cycle (N elements = N*DATA_W bits)
//                 wr_sel = 0 -> A, 1 -> B ; wr_row = row index ; always
//                 written into the SHADOW bank.
//   Read side   : identical to the Phase I buffer (feed, k_idx -> a_vec,b_vec)
//                 but reads the ACTIVE bank.
//
//   Rule for the host: finish writing the shadow bank before pulsing start.
//
//   OUT_REG = 1 (timing option): a_vec / b_vec come from registers instead of
//   directly from the read multiplexer. This removes the path
//   "controller state -> read mux -> multiplier -> adder" (the critical path
//   found by nextpnr) at the cost of one cycle of latency; the controller
//   adds one drain cycle (BUF_REG parameter).
// =============================================================================
`timescale 1ns / 1ps

module matrix_buffer_pp #(
    parameter N       = 4,
    parameter DATA_W  = 8,
    parameter OUT_REG = 0,
    parameter KW      = (N > 1) ? $clog2(N) : 1
) (
    input  wire                 clk,
    input  wire                 rst_n,
    // write interface (shadow bank)
    input  wire                 wr_en,
    input  wire                 wr_sel,      // 0 = A, 1 = B
    input  wire [KW-1:0]        wr_row,
    input  wire [N*DATA_W-1:0]  wr_data,     // lane c = element [row][c]
    // bank control
    input  wire                 swap,
    output reg                  active,      // bank currently read by the array
    // read interface (active bank)
    input  wire                 feed,
    input  wire [KW-1:0]        k_idx,
    output wire [N*DATA_W-1:0]  a_vec,       // lane i = A[i][k]
    output wire [N*DATA_W-1:0]  b_vec        // lane j = B[k][j]
);

    localparam MW = N*N*DATA_W;

    reg [MW-1:0] a_bank0, a_bank1, b_bank0, b_bank1;

    integer c;

    // ---------------- bank pointer ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)    active <= 1'b0;
        else if (swap) active <= ~active;
    end

    // ---------------- row writes into the shadow bank ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_bank0 <= {MW{1'b0}};  a_bank1 <= {MW{1'b0}};
            b_bank0 <= {MW{1'b0}};  b_bank1 <= {MW{1'b0}};
        end else if (wr_en) begin
            for (c = 0; c < N; c = c + 1) begin
                case ({wr_sel, active})
                    2'b01: a_bank0[(wr_row*N + c)*DATA_W +: DATA_W] <= wr_data[c*DATA_W +: DATA_W];
                    2'b00: a_bank1[(wr_row*N + c)*DATA_W +: DATA_W] <= wr_data[c*DATA_W +: DATA_W];
                    2'b11: b_bank0[(wr_row*N + c)*DATA_W +: DATA_W] <= wr_data[c*DATA_W +: DATA_W];
                    2'b10: b_bank1[(wr_row*N + c)*DATA_W +: DATA_W] <= wr_data[c*DATA_W +: DATA_W];
                endcase
            end
        end
    end

    // ---------------- reads from the active bank ----------------
    wire [MW-1:0] a_act = active ? a_bank1 : a_bank0;
    wire [MW-1:0] b_act = active ? b_bank1 : b_bank0;

    wire [N*DATA_W-1:0] a_sel, b_sel;

    genvar l;
    generate
        for (l = 0; l < N; l = l + 1) begin : g_lane
            assign a_sel[l*DATA_W +: DATA_W] =
                feed ? a_act[(l*N + k_idx)*DATA_W +: DATA_W] : {DATA_W{1'b0}};
            assign b_sel[l*DATA_W +: DATA_W] =
                feed ? b_act[(k_idx*N + l)*DATA_W +: DATA_W] : {DATA_W{1'b0}};
        end

        if (OUT_REG != 0) begin : g_outreg
            reg [N*DATA_W-1:0] a_r, b_r;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    a_r <= {(N*DATA_W){1'b0}};
                    b_r <= {(N*DATA_W){1'b0}};
                end else begin
                    a_r <= a_sel;          // zeros whenever feed = 0
                    b_r <= b_sel;
                end
            end
            assign a_vec = a_r;
            assign b_vec = b_r;
        end else begin : g_comb
            assign a_vec = a_sel;
            assign b_vec = b_sel;
        end
    endgenerate

endmodule
