// =============================================================================
// File        : requant.v
// Project     : Systolic Array Matrix Multiplication Accelerator (CSA-222)
// Description : Output requantisation: wide accumulator -> narrow fixed point.
//
//   The array produces C in Q24.8 (32 bit). To feed the result to the next
//   layer of a neural network (or back into the array as a new A matrix) it
//   must be converted to the operand format again, e.g. Q4.4 (8 bit).
//
//   Steps (purely combinational):
//     1. Round to nearest   : add 0.5 LSB of the output format
//                             (= 2^(SH-1) in input LSBs, SH = IN_FRAC-OUT_FRAC)
//     2. Shift              : arithmetic shift right by SH bits
//     3. Saturate           : clamp to [-2^(OUT_W-1), 2^(OUT_W-1)-1]
//                             and raise 'sat' when clamping happened
//
//   Default : Q24.8 -> Q4.4   (SH = 4, range -8.0 .. +7.9375)
//   Q8.8    : set OUT_W = 16, OUT_FRAC = 8 (SH = 0, saturation only)
//
//   Rounding mode: round-half-up (ties go towards +infinity), the same as
//   floor(x + 0.5). The Python golden model uses exactly the same rule.
// =============================================================================
`timescale 1ns / 1ps

module requant #(
    parameter IN_W     = 32,
    parameter IN_FRAC  = 8,
    parameter OUT_W    = 8,
    parameter OUT_FRAC = 4
) (
    input  wire signed [IN_W-1:0]  din,
    output wire signed [OUT_W-1:0] dout,
    output wire                    sat     // 1 = value was clamped
);

    localparam SH = IN_FRAC - OUT_FRAC;    // fractional bits to drop (>= 0)

    // one extra bit so the rounding addition can never overflow
    wire signed [IN_W:0] din_ext = {din[IN_W-1], din};
    wire signed [IN_W:0] rounded;
    wire signed [IN_W:0] shifted;

    generate
        if (SH > 0) begin : g_round
            assign rounded = din_ext + ({{IN_W{1'b0}}, 1'b1} <<< (SH-1));
            assign shifted = rounded >>> SH;
        end else begin : g_noround
            assign rounded = din_ext;
            assign shifted = din_ext;
        end
    endgenerate

    // saturation limits, sign-extended to IN_W+1 bits
    wire signed [IN_W:0] max_v = {{(IN_W-OUT_W+2){1'b0}}, {(OUT_W-1){1'b1}}};
    wire signed [IN_W:0] min_v = {{(IN_W-OUT_W+2){1'b1}}, {(OUT_W-1){1'b0}}};

    wire too_big   = (shifted > max_v);
    wire too_small = (shifted < min_v);

    assign sat  = too_big | too_small;
    assign dout = too_big   ? max_v[OUT_W-1:0] :
                  too_small ? min_v[OUT_W-1:0] :
                              shifted[OUT_W-1:0];

endmodule
