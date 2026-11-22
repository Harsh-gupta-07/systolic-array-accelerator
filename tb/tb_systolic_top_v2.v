// =============================================================================
// File        : tb_systolic_top_v2.v
// Description : System testbench for the Phase II accelerator.
//
//   Uses tests/vectors/v2_vectors.hex (8 directed + 200 random products, with
//   golden raw results AND golden requantised Q4.4 results).
//
//   Part A - SERIAL mode     : load -> start -> wait done -> read, one product
//                              at a time (how the Phase I design is used).
//   Part B - OVERLAPPED mode : the host loads product t+1 into the shadow
//                              bank while product t is computed, starts t+1
//                              the moment t is done, and reads the results
//                              of t while t+1 runs (ping-pong + result buffer).
//
//   Every element is checked (raw Q24.8, requantised Q4.4 and saturation
//   flag). Throughput is read from the on-chip performance counters.
//   Override MUL_PIPE from the command line: iverilog -P tb_systolic_top_v2.MUL_PIPE=1
// Run  : cd sim && make top2
// =============================================================================
`timescale 1ns / 1ps

`ifndef VEC_DIR
 `define VEC_DIR "../tests/vectors/"
`endif

module tb_systolic_top_v2;

    parameter MUL_PIPE = 0;
    parameter BUF_REG  = 0;

    localparam N = 4, DATA_W = 8, ACC_W = 32, OUT_W = 8, KW = 2;
    localparam NN = N*N, WPT = 4*NN;          // words per test
    localparam MAX_TESTS = 512;

    reg                  clk, rst_n, start, acc_mode;
    reg                  wr_en, wr_sel, perf_clr;
    reg  [KW-1:0]        wr_row, rd_row;
    reg  [N*DATA_W-1:0]  wr_data;
    reg  [1:0]           perf_sel;
    wire                 busy, done;
    wire [N*ACC_W-1:0]   rd_data;
    wire [N*OUT_W-1:0]   rd_q;
    wire [N-1:0]         rd_sat;
    wire [31:0]          perf_data;

    reg  [31:0] vec [0:MAX_TESTS*WPT-1];
    reg  [31:0] cnt [0:0];
    integer num_tests, t, errors, checks;
    integer cyc_total, cyc_mm, cyc_busy;

    systolic_top_v2 #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W), .MUL_PIPE(MUL_PIPE), .BUF_REG(BUF_REG),
                      .OUT_W(OUT_W), .OUT_FRAC(4)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .acc_mode(acc_mode),
        .busy(busy), .done(done),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_row(wr_row), .wr_data(wr_data),
        .rd_row(rd_row), .rd_data(rd_data), .rd_q(rd_q), .rd_sat(rd_sat),
        .perf_clr(perf_clr), .perf_sel(perf_sel), .perf_data(perf_data)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // ---------------- host tasks ----------------
    task load_test;                      // 8 cycles: 4 rows of A, 4 rows of B
        input integer tt;
        integer r, c, base;
        begin
            base = tt*WPT;
            for (r = 0; r < 2*N; r = r + 1) begin
                wr_en = 1; wr_sel = (r >= N); wr_row = r % N;
                for (c = 0; c < N; c = c + 1)
                    wr_data[c*DATA_W +: DATA_W] = vec[base + r*N + c][DATA_W-1:0];
                @(posedge clk); #1;
            end
            wr_en = 0;
        end
    endtask

    task read_check;                     // 4 cycles: one row of C per cycle
        input integer tt;
        integer r, c, base;
        reg [31:0] exp_c, exp_q;
        begin
            base = tt*WPT;
            for (r = 0; r < N; r = r + 1) begin
                rd_row = r; #1;
                for (c = 0; c < N; c = c + 1) begin
                    exp_c = vec[base + 2*NN + r*N + c];
                    exp_q = vec[base + 3*NN + r*N + c];
                    checks = checks + 1;
                    if (rd_data[c*ACC_W +: ACC_W] !== exp_c ||
                        rd_q[c*OUT_W +: OUT_W]   !== exp_q[7:0] ||
                        rd_sat[c]                !== exp_q[8]) begin
                        errors = errors + 1;
                        if (errors < 10)
                            $display("  [FAIL] test %0d C[%0d][%0d]: raw %0d exp %0d | q %0d exp %0d | sat %0d exp %0d",
                                tt, r, c, $signed(rd_data[c*ACC_W +: ACC_W]), $signed(exp_c),
                                $signed(rd_q[c*OUT_W +: OUT_W]), $signed(exp_q[7:0]),
                                rd_sat[c], exp_q[8]);
                    end
                end
                @(posedge clk); #1;
            end
        end
    endtask

    task pulse_start;
        input mode;
        begin
            start = 1; acc_mode = mode;
            @(posedge clk); #1;
            start = 0; acc_mode = 0;
        end
    endtask

    task wait_done;
        begin
            while (!done) begin @(posedge clk); #1; end
        end
    endtask

    task clear_perf;
        begin perf_clr = 1; @(posedge clk); #1; perf_clr = 0; end
    endtask

    task read_perf;
        begin
            perf_sel = 0; #1; cyc_total = perf_data;
            perf_sel = 1; #1; cyc_busy  = perf_data;
            perf_sel = 3; #1; cyc_mm    = perf_data;
        end
    endtask

    // ---------------- main ----------------
    initial begin
        $dumpfile("tb_systolic_top_v2.vcd");
        $dumpvars(0, tb_systolic_top_v2);

        $readmemh({`VEC_DIR, "v2_count.hex"}, cnt);
        num_tests = cnt[0];
        if (num_tests === 32'bx || num_tests == 0) begin
            $display(" RESULT: FAILED - vector files not found in %0s", `VEC_DIR);
            $finish;
        end
        if (num_tests > MAX_TESTS) num_tests = MAX_TESTS;
        $readmemh({`VEC_DIR, "v2_vectors.hex"}, vec, 0, num_tests*WPT - 1);

        $display("==================================================");
        $display(" tb_systolic_top_v2 : %0d tests, MUL_PIPE = %0d, BUF_REG = %0d", num_tests, MUL_PIPE, BUF_REG);
        $display("==================================================");

        rst_n = 0; start = 0; acc_mode = 0; wr_en = 0; wr_sel = 0; wr_row = 0;
        wr_data = 0; rd_row = 0; perf_clr = 0; perf_sel = 0;
        errors = 0; checks = 0;
        #22 rst_n = 1;
        @(posedge clk); #1;

        // ------------- Part A: serial -------------
        clear_perf;
        for (t = 0; t < num_tests; t = t + 1) begin
            load_test(t);
            pulse_start(1'b0);
            wait_done;
            @(posedge clk); #1;           // result captured at end of DONE
            read_check(t);
        end
        read_perf;
        $display("  Part A (serial)     : %0d products, %0d cycles -> %0d.%02d cycles/product, busy %0d%%",
                 cyc_mm, cyc_total, cyc_total / cyc_mm, (100*cyc_total / cyc_mm) % 100,
                 100*cyc_busy / cyc_total);

        // ------------- Part B: overlapped -------------
        clear_perf;
        load_test(0);
        pulse_start(1'b0);
        if (num_tests > 1) load_test(1);
        for (t = 0; t < num_tests; t = t + 1) begin
            wait_done;
            if (t + 1 < num_tests) begin
                pulse_start(1'b0);        // next product starts immediately
                fork
                    read_check(t);        // results of t from the result buffer
                    if (t + 2 < num_tests) load_test(t + 2);   // shadow bank
                join
            end else begin
                @(posedge clk); #1;
                read_check(t);
            end
        end
        read_perf;
        $display("  Part B (overlapped) : %0d products, %0d cycles -> %0d.%02d cycles/product, busy %0d%%",
                 cyc_mm, cyc_total, cyc_total / cyc_mm, (100*cyc_total / cyc_mm) % 100,
                 100*cyc_busy / cyc_total);

        $display("--------------------------------------------------");
        if (errors == 0) $display(" RESULT: ALL %0d ELEMENT CHECKS PASSED (raw + Q4.4 + sat), 2 x %0d products",
                                  checks, num_tests);
        else             $display(" RESULT: FAILED (%0d / %0d element checks)", errors, checks);
        $display("==================================================");
        $finish;
    end

    initial begin
        #5000000 $display(" TIMEOUT"); $finish;
    end

endmodule
