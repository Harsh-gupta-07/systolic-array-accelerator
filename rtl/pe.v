// =============================================================================
// File        : pe.v
// Project     : Systolic Array Matrix Multiplication Accelerator (CSA-222)
// Description : Output-stationary Processing Element (PE).
//
//              b_in (from north)
//                 |
//                 v
//   a_in --->  [  MAC  ] ---> a_out (to east,  registered, 1-cycle delay)
//   (west)        |
//                 v
//              b_out (to south, registered, 1-cycle delay)
//
//   Each cycle the PE
//     1. multiplies the operands arriving on a_in and b_in and adds the
//        product to its local accumulator (the "stationary" output C[i][j]),
//     2. forwards a_in to its east neighbour and b_in to its south neighbour
//        through pipeline registers.
//
//   clear : zeroes the accumulator AND the forwarding registers so that a new
//           matrix product starts from a clean pipeline.
//   en    : global advance/accumulate enable (pipeline freezes when 0).
// =============================================================================
`timescale 1ns / 1ps

module pe #(
    parameter DATA_W   = 8,
    parameter ACC_W    = 32,
    parameter MUL_PIPE = 0     // passed to mac_unit (Phase II)
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,
    input  wire                     en,
    input  wire signed [DATA_W-1:0] a_in,     // from west neighbour
    input  wire signed [DATA_W-1:0] b_in,     // from north neighbour
    output reg  signed [DATA_W-1:0] a_out,    // to east neighbour
    output reg  signed [DATA_W-1:0] b_out,    // to south neighbour
    output wire signed [ACC_W-1:0]  acc_out   // stationary result C[i][j]
);

    // ---------------- Multiply-accumulate datapath ----------------
    mac_unit #(
        .DATA_W   (DATA_W),
        .ACC_W    (ACC_W),
        .MUL_PIPE (MUL_PIPE)
    ) u_mac (
        .clk   (clk),
        .rst_n (rst_n),
        .clear (clear),
        .en    (en),
        .a     (a_in),
        .b     (b_in),
        .acc   (acc_out)
    );

    // ---------------- Systolic forwarding registers ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out <= {DATA_W{1'b0}};
            b_out <= {DATA_W{1'b0}};
        end else if (clear) begin
            a_out <= {DATA_W{1'b0}};
            b_out <= {DATA_W{1'b0}};
        end else if (en) begin
            a_out <= a_in;
            b_out <= b_in;
        end
    end

endmodule
