// =============================================================================
// File        : perf_counters.v
// Project     : Systolic Array Matrix Multiplication Accelerator (CSA-222)
// Description : Hardware performance counters (Phase II).
//
//   Like the cycle/instruction counters of a CPU, these let software measure
//   the accelerator from the inside instead of relying on the testbench.
//
//   sel | counter          | meaning
//   ----+------------------+-----------------------------------------------
//    0  | total_cycles     | clock cycles since the last perf_clr
//    1  | busy_cycles      | cycles in CLEAR / FEED / DRAIN
//    2  | en_cycles        | cycles in which the array advanced (FEED+DRAIN)
//    3  | matmul_count     | completed products (done pulses)
//
//   Derived metrics (computed by software, see model/perf_model.py)
//     cycles per product = total_cycles / matmul_count
//     useful MACs        = matmul_count * N^3
//     PE utilisation     = useful MACs / (N^2 * total_cycles)
// =============================================================================
`timescale 1ns / 1ps

module perf_counters #(
    parameter CNT_W = 32
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              perf_clr,
    input  wire              busy,
    input  wire              en,
    input  wire              done,
    input  wire [1:0]        sel,
    output reg  [CNT_W-1:0]  data
);

    reg [CNT_W-1:0] total_cycles, busy_cycles, en_cycles, matmul_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_cycles <= 0; busy_cycles <= 0; en_cycles <= 0; matmul_count <= 0;
        end else if (perf_clr) begin
            total_cycles <= 0; busy_cycles <= 0; en_cycles <= 0; matmul_count <= 0;
        end else begin
            total_cycles <= total_cycles + 1'b1;
            if (busy) busy_cycles  <= busy_cycles  + 1'b1;
            if (en)   en_cycles    <= en_cycles    + 1'b1;
            if (done) matmul_count <= matmul_count + 1'b1;
        end
    end

    always @(*) begin
        case (sel)
            2'd0:    data = total_cycles;
            2'd1:    data = busy_cycles;
            2'd2:    data = en_cycles;
            default: data = matmul_count;
        endcase
    end

endmodule
