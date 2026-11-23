// =============================================================================
// File        : tb_tiled_gemm.v
// Description : Large matrix multiply (SIZE x SIZE) on the 4x4 accelerator
//               using block tiling and the accumulate mode of
//               systolic_top_v2. The testbench acts as the host driver:
//
//     T = SIZE / 4 tiles per dimension
//     for I in 0..T-1, for J in 0..T-1:
//         for K in 0..T-1:
//             load A(I,K) and B(K,J) into the shadow bank
//             start with acc_mode = (K > 0)      // K>0: keep adding
//         read C(I,J) from the result buffer
//
//   Loads, computation and read-back are overlapped exactly as in the
//   streaming test (ping-pong buffers + result buffer). The full C matrix
//   is checked against the golden model (tests/vectors/tiledSIZE_vectors.hex).
//
//   +define+SIZE=8 (default) or +define+SIZE=12
// Run  : cd sim && make tiled
// =============================================================================
`timescale 1ns / 1ps

`ifndef VEC_DIR
 `define VEC_DIR "../tests/vectors/"
`endif
`ifndef SIZE
 `define SIZE 8
`endif

module tb_tiled_gemm;

    localparam N = 4, DATA_W = 8, ACC_W = 32, OUT_W = 8, KW = 2;
    localparam S = `SIZE;
    localparam T = S / N;               // tiles per dimension
    localparam JOBS = T*T*T;            // tile products

    reg                  clk, rst_n, start, acc_mode, wr_en, wr_sel, perf_clr;
    reg  [KW-1:0]        wr_row, rd_row;
    reg  [N*DATA_W-1:0]  wr_data;
    reg  [1:0]           perf_sel;
    wire                 busy, done;
    wire [N*ACC_W-1:0]   rd_data;
    wire [N*OUT_W-1:0]   rd_q;
    wire [N-1:0]         rd_sat;
    wire [31:0]          perf_data;

    reg [31:0] vec [0:3*S*S-1];         // A (SxS), B (SxS), C (SxS)
    integer job, errors, checks, cyc_total, cyc_busy, mm;
    reg [8*128:1] fname;

    systolic_top_v2 #(.N(N)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .acc_mode(acc_mode),
        .busy(busy), .done(done),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_row(wr_row), .wr_data(wr_data),
        .rd_row(rd_row), .rd_data(rd_data), .rd_q(rd_q), .rd_sat(rd_sat),
        .perf_clr(perf_clr), .perf_sel(perf_sel), .perf_data(perf_data));

    initial clk = 0;
    always #5 clk = ~clk;

    // job number -> tile coordinates (K innermost)
    function integer tI; input integer n; tI = n / (T*T);   endfunction
    function integer tJ; input integer n; tJ = (n / T) % T; endfunction
    function integer tK; input integer n; tK = n % T;       endfunction

    task load_job;                       // 8 cycles: A(I,K) rows, B(K,J) rows
        input integer n;
        integer r, c, I, J, K;
        begin
            I = tI(n); J = tJ(n); K = tK(n);
            for (r = 0; r < 2*N; r = r + 1) begin
                wr_en = 1; wr_sel = (r >= N); wr_row = r % N;
                for (c = 0; c < N; c = c + 1)
                    if (r < N)   // A element (I*N + r, K*N + c)
                        wr_data[c*DATA_W +: DATA_W] = vec[(I*N + r)*S + K*N + c][7:0];
                    else         // B element (K*N + r-N, J*N + c)
                        wr_data[c*DATA_W +: DATA_W] = vec[S*S + (K*N + r - N)*S + J*N + c][7:0];
                @(posedge clk); #1;
            end
            wr_en = 0;
        end
    endtask

    task read_tile;                      // 4 cycles: C(I,J)
        input integer n;
        integer r, c, I, J;
        begin
            I = tI(n); J = tJ(n);
            for (r = 0; r < N; r = r + 1) begin
                rd_row = r; #1;
                for (c = 0; c < N; c = c + 1) begin
                    checks = checks + 1;
                    if (rd_data[c*ACC_W +: ACC_W] !== vec[2*S*S + (I*N + r)*S + J*N + c]) begin
                        errors = errors + 1;
                        if (errors < 10)
                            $display("  [FAIL] C[%0d][%0d] got %0d expected %0d", I*N + r, J*N + c,
                                     $signed(rd_data[c*ACC_W +: ACC_W]),
                                     $signed(vec[2*S*S + (I*N + r)*S + J*N + c]));
                    end
                end
                @(posedge clk); #1;
            end
        end
    endtask

    task pulse_start;
        input mode;
        begin
            start = 1; acc_mode = mode; @(posedge clk); #1; start = 0; acc_mode = 0;
        end
    endtask

    initial begin
        $dumpfile("tb_tiled_gemm.vcd");
        $dumpvars(0, tb_tiled_gemm);
        $sformat(fname, "%stiled%0d_vectors.hex", `VEC_DIR, S);
        $readmemh(fname, vec);
        if (^vec[3*S*S-1] === 1'bx) begin
            $display(" RESULT: TILED GEMM FAILED - could not read %0s", fname);
            $finish;
        end
        $display("==================================================");
        $display(" tb_tiled_gemm : %0dx%0d GEMM on a %0dx%0d array (%0d tile products)",
                 S, S, N, N, JOBS);
        $display("==================================================");
        rst_n = 0; start = 0; acc_mode = 0; wr_en = 0; wr_sel = 0; wr_row = 0;
        wr_data = 0; rd_row = 0; perf_clr = 0; perf_sel = 0; errors = 0; checks = 0;
        #22 rst_n = 1;
        @(posedge clk); #1;
        perf_clr = 1; @(posedge clk); #1; perf_clr = 0;

        load_job(0);
        pulse_start(1'b0);
        if (JOBS > 1) load_job(1);
        for (job = 0; job < JOBS; job = job + 1) begin
            while (!done) begin @(posedge clk); #1; end
            if (job + 1 < JOBS) begin
                pulse_start(tK(job + 1) != 0);       // accumulate unless new tile
                fork
                    if (tK(job) == T-1) read_tile(job);       // C(I,J) complete
                    if (job + 2 < JOBS) load_job(job + 2);
                join
            end else begin
                @(posedge clk); #1;
                read_tile(job);
            end
        end

        perf_sel = 0; #1; cyc_total = perf_data;
        perf_sel = 1; #1; cyc_busy  = perf_data;
        perf_sel = 3; #1; mm        = perf_data;
        $display("  tile products      : %0d", mm);
        $display("  total cycles       : %0d  (%0d.%01d cycles per tile product)",
                 cyc_total, cyc_total / mm, (10*cyc_total / mm) % 10);
        $display("  array busy         : %0d%%", 100*cyc_busy / cyc_total);
        $display("  sequential (1 MAC) : %0d cycles  ->  speed-up %0d.%01dx",
                 S*S*S, S*S*S / cyc_total, (10*S*S*S / cyc_total) % 10);
        $display("--------------------------------------------------");
        if (errors == 0) $display(" RESULT: TILED %0dx%0d GEMM PASSED (%0d elements)", S, S, checks);
        else             $display(" RESULT: TILED GEMM FAILED (%0d / %0d)", errors, checks);
        $display("==================================================");
        $finish;
    end

    initial begin #2000000 $display(" TIMEOUT"); $finish; end

endmodule
