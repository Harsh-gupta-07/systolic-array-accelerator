// =============================================================================
// File        : tb_ws_top.v
// Description : Testbench for the weight-stationary streaming design.
//   Loads B (4x4) once, then streams A row by row and checks every C row
//   against tests/vectors/ws_vectors.hex (golden model, A is 16 x 4).
//     Run 1 : M = 4  rows  (same problem size as one OS product)
//     Run 2 : M = 16 rows  streamed back to back (weights reused 16 times)
//   Reports total cycles (weight load -> last result) for both runs.
// Run  : cd sim && make ws
// =============================================================================
`timescale 1ns / 1ps

`ifndef VEC_DIR
 `define VEC_DIR "../tests/vectors/"
`endif

module tb_ws_top;

    localparam N = 4, DATA_W = 8, ACC_W = 32, M_MAX = 16;

    reg                  clk, rst_n, w_load, a_valid;
    reg  [N*DATA_W-1:0]  w_row, a_row;
    wire                 c_valid;
    wire [N*ACC_W-1:0]   c_row;

    // A: 16x4 = 64 words, B: 16 words, C: 64 words
    reg [31:0] vec [0:M_MAX*N + N*N + M_MAX*N - 1];
    integer errors, out_row, cyc, t_start, run_m, r, c;

    ws_top #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst_n(rst_n), .w_load(w_load), .w_row(w_row),
        .a_valid(a_valid), .a_row(a_row), .c_valid(c_valid), .c_row(c_row));

    initial clk = 0;
    always #5 clk = ~clk;

    // result checker: runs in parallel with the stimulus
    always @(posedge clk) begin
        if (c_valid && out_row < run_m) begin
            for (c = 0; c < N; c = c + 1)
                if (c_row[c*ACC_W +: ACC_W] !== vec[M_MAX*N + N*N + out_row*N + c]) begin
                    errors = errors + 1;
                    $display("  [FAIL] C[%0d][%0d] = %0d expected %0d", out_row, c,
                             $signed(c_row[c*ACC_W +: ACC_W]),
                             $signed(vec[M_MAX*N + N*N + out_row*N + c]));
                end
            out_row = out_row + 1;
            cyc = ($time - t_start) / 10;     // cycles from first w_load cycle, inclusive
        end
    end

    task run;
        input integer m;
        begin
            run_m = m; out_row = 0;
            @(posedge clk); #1;
            t_start = $time - 1;               // time of the edge that starts cycle 0
            // 1. weight load: B rows N-1 .. 0
            for (r = N-1; r >= 0; r = r - 1) begin
                w_load = 1;
                for (c = 0; c < N; c = c + 1)
                    w_row[c*DATA_W +: DATA_W] = vec[M_MAX*N + r*N + c][DATA_W-1:0];
                @(posedge clk); #1;
            end
            w_load = 0;
            // 2. stream m rows of A back to back
            for (r = 0; r < m; r = r + 1) begin
                a_valid = 1;
                for (c = 0; c < N; c = c + 1)
                    a_row[c*DATA_W +: DATA_W] = vec[r*N + c][DATA_W-1:0];
                @(posedge clk); #1;
            end
            a_valid = 0; a_row = 0;
            // 3. wait for the last result
            while (out_row < m) @(posedge clk);
            #1;
            $display("  M = %2d rows : %0d rows checked, %0d cycles = load %0d + stream %0d + latency %0d",
                     m, out_row, cyc, N, m, 2*N-1);
            repeat (2*N) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        $dumpfile("tb_ws_top.vcd");
        $dumpvars(0, tb_ws_top);
        $readmemh({`VEC_DIR, "ws_vectors.hex"}, vec);
        if (^vec[M_MAX*N + N*N + M_MAX*N - 1] === 1'bx) begin
            $display(" RESULT: FAILED - ws_vectors.hex not found in %0s", `VEC_DIR);
            $finish;
        end
        $display("==================================================");
        $display(" tb_ws_top : weight-stationary %0dx%0d array", N, N);
        $display("==================================================");
        rst_n = 0; w_load = 0; a_valid = 0; w_row = 0; a_row = 0;
        errors = 0; run_m = 0; out_row = 0;
        #22 rst_n = 1;
        run(4);
        run(16);
        $display("--------------------------------------------------");
        if (errors == 0) $display(" RESULT: WS ARRAY PASSED (4 + 16 rows)");
        else             $display(" RESULT: WS ARRAY FAILED (%0d errors)", errors);
        $display("==================================================");
        $finish;
    end

endmodule
