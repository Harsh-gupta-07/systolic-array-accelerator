// =============================================================================
// File        : mac_unit.v
// Project     : Systolic Array Matrix Multiplication Accelerator (CSA-222)
// Description : Signed fixed-point Multiply-Accumulate (MAC) unit.
//
//   acc <= acc + a * b          (when en = 1)
//   acc <= 0                    (when clear = 1, has priority over en)
//
// Number format
//   Operands a, b : signed Q4.4  (DATA_W = 8, FRAC_W = 4)  range [-8.0, +7.9375]
//   Product       : signed Q8.8  (2*DATA_W = 16 bits)
//   Accumulator   : signed Q24.8 (ACC_W = 32 bits) -> no overflow is possible
//                   for N <= 2^16 accumulations of the largest product.
//
// Phase II: optional multiplier pipeline register (MUL_PIPE)
//   MUL_PIPE = 0 : multiply and add in the same cycle (Phase I behaviour).
//                  Critical path = multiplier + 32-bit adder.
//   MUL_PIPE = 1 : the product, en and clear are registered first and the
//                  addition happens one cycle later. The critical path is
//                  split in two (higher Fmax) at the cost of one extra cycle
//                  of latency. Throughput is still one MAC per cycle.
//                  The controller adds MUL_PIPE cycles to its drain phase.
// =============================================================================
`timescale 1ns / 1ps

module mac_unit #(
    parameter DATA_W   = 8,   // operand width (Q4.4)
    parameter ACC_W    = 32,  // accumulator width (Q24.8)
    parameter MUL_PIPE = 0    // 0 = combinational multiply, 1 = registered product
) (
    input  wire                     clk,
    input  wire                     rst_n,   // asynchronous active-low reset
    input  wire                     clear,   // synchronous clear of accumulator
    input  wire                     en,      // accumulate enable
    input  wire signed [DATA_W-1:0] a,
    input  wire signed [DATA_W-1:0] b,
    output reg  signed [ACC_W-1:0]  acc
);

    // Full-precision signed product (Q8.8)
    wire signed [2*DATA_W-1:0] product;
    assign product = a * b;

    // Stage-1 signals seen by the accumulator (direct or registered)
    wire signed [2*DATA_W-1:0] prod_s;
    wire                       en_s;
    wire                       clear_s;

    generate
        if (MUL_PIPE != 0) begin : g_pipe
            reg signed [2*DATA_W-1:0] prod_r;
            reg                       en_r, clear_r;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    prod_r  <= {(2*DATA_W){1'b0}};
                    en_r    <= 1'b0;
                    clear_r <= 1'b0;
                end else begin
                    prod_r  <= product;
                    en_r    <= en;
                    clear_r <= clear;
                end
            end
            assign prod_s  = prod_r;
            assign en_s    = en_r;
            assign clear_s = clear_r;
        end else begin : g_comb
            assign prod_s  = product;
            assign en_s    = en;
            assign clear_s = clear;
        end
    endgenerate

    // Sign-extend product to accumulator width
    wire signed [ACC_W-1:0] product_ext;
    assign product_ext = {{(ACC_W-2*DATA_W){prod_s[2*DATA_W-1]}}, prod_s};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc <= {ACC_W{1'b0}};
        else if (clear_s)
            acc <= {ACC_W{1'b0}};
        else if (en_s)
            acc <= acc + product_ext;
    end

endmodule
