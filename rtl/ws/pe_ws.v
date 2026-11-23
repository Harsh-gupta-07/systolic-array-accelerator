// =============================================================================
// File        : pe_ws.v
// Project     : Systolic Array Matrix Multiplication Accelerator (CSA-222)
// Description : Weight-stationary Processing Element (alternative dataflow).
//
//                w_in / p_in (from north)
//                     |
//                     v
//   a_in (west) --> [ W ] --> a_out (east)        W   = stationary weight B[k][j]
//                     |                           p   = partial sum moving south
//                     v
//                w_out / p_out (to south)
//
//   Weight load (load_w = 1): weights shift down the column, one PE per cycle.
//   Compute     (en = 1)    : p_out <= p_in + a_in * W ;  a_out <= a_in
//
//   Compared with the output-stationary PE (pe.v):
//     * B stays inside the PE instead of moving -> it is fetched only once.
//     * The 32-bit partial sum moves between PEs instead of the 8-bit B value,
//       so vertical wiring is 4x wider.
//     * The result leaves the array at the bottom, so there is no read-out mux
//       and the array can stream an unlimited number of rows of A.
//   (This is the dataflow of Google's TPU matrix unit.)
// =============================================================================
`timescale 1ns / 1ps

module pe_ws #(
    parameter DATA_W = 8,
    parameter ACC_W  = 32
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     en,
    input  wire                     load_w,
    input  wire signed [DATA_W-1:0] w_in,
    output reg  signed [DATA_W-1:0] w_out,    // = stationary weight
    input  wire signed [DATA_W-1:0] a_in,
    output reg  signed [DATA_W-1:0] a_out,
    input  wire signed [ACC_W-1:0]  p_in,
    output reg  signed [ACC_W-1:0]  p_out
);

    wire signed [2*DATA_W-1:0] product = a_in * w_out;
    wire signed [ACC_W-1:0]    product_ext = {{(ACC_W-2*DATA_W){product[2*DATA_W-1]}}, product};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      w_out <= {DATA_W{1'b0}};
        else if (load_w) w_out <= w_in;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out <= {DATA_W{1'b0}};
            p_out <= {ACC_W{1'b0}};
        end else if (en) begin
            a_out <= a_in;
            p_out <= p_in + product_ext;
        end
    end

endmodule
