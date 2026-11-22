// =============================================================================
// File        : tb_requant.v
// Description : Self-checking testbench for requant.v (Q24.8 -> Q4.4).
//   Part 1 - directed cases printed with their real values (for the report)
//   Part 2 - 2000 golden-model vectors: every rounding boundary (+/- 0.5 LSB),
//            both saturation limits, the 32-bit extremes and random values.
// Run  : cd sim && make requant
// =============================================================================
`timescale 1ns / 1ps

`ifndef VEC_DIR
 `define VEC_DIR "../tests/vectors/"
`endif

module tb_requant;

    reg  signed [31:0] din;
    wire signed [7:0]  dout;
    wire               sat;

    reg  [31:0] vec [0:2*4096-1];
    reg  [31:0] cnt [0:0];
    integer i, n, errors = 0;

    requant #(.IN_W(32), .IN_FRAC(8), .OUT_W(8), .OUT_FRAC(4)) dut (
        .din(din), .dout(dout), .sat(sat));

    task show;
        input signed [31:0] v;
        begin
            din = v; #1;
            $display("    din = %8d (%9.4f)  ->  q = %4d (%8.4f)  sat = %0d",
                     din, din / 256.0, dout, dout / 16.0, sat);
        end
    endtask

    initial begin
        $display("==================================================");
        $display(" tb_requant : Q24.8 -> Q4.4, round-half-up + saturate");
        $display("==================================================");
        $display("  Directed examples:");
        show(32'sd864);        //  3.375    -> 3.375 exactly (54)
        show(32'sd872);        //  3.40625  -> rounds up to 3.4375 (55)
        show(32'sd8);          //  0.03125  = half LSB -> rounds up to 0.0625
        show(-32'sd8);         // -0.03125  = half LSB -> rounds up to 0.0
        show(32'sd2040);       //  7.96875  -> would round to 8.0 -> saturates 7.9375
        show(-32'sd2048);      // -8.0      -> fits exactly
        show(-32'sd2057);      // just below -8.0 - 0.5 LSB -> saturates
        show(32'sd65536);      // 256.0     -> saturates to 7.9375

        $readmemh({`VEC_DIR, "requant_count.hex"}, cnt);
        n = cnt[0];
        if (n === 32'bx || n == 0) begin
            $display(" RESULT: FAILED - vector files not found in %0s", `VEC_DIR);
            $finish;
        end
        $readmemh({`VEC_DIR, "requant_vectors.hex"}, vec, 0, 2*n-1);
        for (i = 0; i < n; i = i + 1) begin
            din = vec[2*i]; #1;
            if ({sat, dout} !== vec[2*i+1][8:0]) begin
                errors = errors + 1;
                if (errors < 10)
                    $display("  [FAIL] din=%0d got q=%0d sat=%0d expected q=%0d sat=%0d",
                             din, dout, sat, $signed(vec[2*i+1][7:0]), vec[2*i+1][8]);
            end
        end
        $display("--------------------------------------------------");
        if (errors == 0) $display(" RESULT: ALL %0d REQUANT VECTORS PASSED", n);
        else             $display(" RESULT: REQUANT FAILED (%0d / %0d)", errors, n);
        $display("==================================================");
        $finish;
    end
endmodule
