// =============================================================================
// File        : tb_scaling.v
// Description : Array-size sweep for systolic_top_v2.
//   Parameter N is set from the command line (iverilog -P tb_scaling.N=8).
//   For the chosen N the testbench
//     1. runs 20 random products one at a time and checks every element
//        against a behavioural triple-loop reference -> start->done latency
//     2. runs 50 random products back to back (overlapped load/compute/read)
//        and reads the performance counters -> cycles per product
//   One summary line is printed in CSV form so a script can collect the
//   results for N = 2, 3, 4, 8, 16 (see sim/Makefile target 'sweep').
// Run  : cd sim && make sweep
// =============================================================================
`timescale 1ns / 1ps

module tb_scaling;

    parameter N        = 4;
    parameter MUL_PIPE = 0;
    parameter BUF_REG  = 0;

    localparam DATA_W = 8, ACC_W = 32, OUT_W = 8;
    localparam KW     = (N > 1) ? $clog2(N) : 1;
    localparam NN     = N*N;
    localparam SER    = 20, OVL = 50, TESTS = SER + OVL;

    reg                  clk, rst_n, start, acc_mode, wr_en, wr_sel, perf_clr;
    reg  [KW-1:0]        wr_row, rd_row;
    reg  [N*DATA_W-1:0]  wr_data;
    reg  [1:0]           perf_sel;
    wire                 busy, done;
    wire [N*ACC_W-1:0]   rd_data;
    wire [N*OUT_W-1:0]   rd_q;
    wire [N-1:0]         rd_sat;
    wire [31:0]          perf_data;

    reg signed [DATA_W-1:0] A   [0:TESTS*NN-1];
    reg signed [DATA_W-1:0] B   [0:TESTS*NN-1];
    reg signed [ACC_W-1:0]  REF [0:TESTS*NN-1];

    integer t, i, j, k, errors, checks, lat, cyc_total, mm, seed;

    systolic_top_v2 #(.N(N), .MUL_PIPE(MUL_PIPE), .BUF_REG(BUF_REG)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .acc_mode(acc_mode),
        .busy(busy), .done(done),
        .wr_en(wr_en), .wr_sel(wr_sel), .wr_row(wr_row), .wr_data(wr_data),
        .rd_row(rd_row), .rd_data(rd_data), .rd_q(rd_q), .rd_sat(rd_sat),
        .perf_clr(perf_clr), .perf_sel(perf_sel), .perf_data(perf_data));

    initial clk = 0;
    always #5 clk = ~clk;

    task load_test;
        input integer tt;
        integer r, c;
        begin
            for (r = 0; r < 2*N; r = r + 1) begin
                wr_en = 1; wr_sel = (r >= N); wr_row = r % N;
                for (c = 0; c < N; c = c + 1)
                    wr_data[c*DATA_W +: DATA_W] = (r < N) ? A[tt*NN + r*N + c]
                                                          : B[tt*NN + (r-N)*N + c];
                @(posedge clk); #1;
            end
            wr_en = 0;
        end
    endtask

    task read_check;
        input integer tt;
        integer r, c;
        begin
            for (r = 0; r < N; r = r + 1) begin
                rd_row = r; #1;
                for (c = 0; c < N; c = c + 1) begin
                    checks = checks + 1;
                    if ($signed(rd_data[c*ACC_W +: ACC_W]) !== REF[tt*NN + r*N + c])
                        errors = errors + 1;
                end
                @(posedge clk); #1;
            end
        end
    endtask

    task pulse_start;
        begin start = 1; @(posedge clk); #1; start = 0; end
    endtask

    task wait_done;
        begin while (!done) begin @(posedge clk); #1; end end
    endtask

    initial begin
        // random operands + behavioural reference
        seed = 1234 + N;
        for (t = 0; t < TESTS; t = t + 1)
            for (i = 0; i < NN; i = i + 1) begin
                A[t*NN + i] = $random(seed);
                B[t*NN + i] = $random(seed);
            end
        for (t = 0; t < TESTS; t = t + 1)
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    REF[t*NN + i*N + j] = 0;
                    for (k = 0; k < N; k = k + 1)
                        REF[t*NN + i*N + j] = REF[t*NN + i*N + j] + A[t*NN + i*N + k] * B[t*NN + k*N + j];
                end

        rst_n = 0; start = 0; acc_mode = 0; wr_en = 0; wr_sel = 0; wr_row = 0;
        wr_data = 0; rd_row = 0; perf_clr = 0; perf_sel = 0; errors = 0; checks = 0;
        #22 rst_n = 1;
        @(posedge clk); #1;

        // 1. serial runs -> latency
        for (t = 0; t < SER; t = t + 1) begin
            load_test(t);
            pulse_start;
            lat = 1;
            while (!done) begin @(posedge clk); #1; lat = lat + 1; end
            @(posedge clk); #1;
            read_check(t);
        end

        // 2. overlapped runs -> throughput
        perf_clr = 1; @(posedge clk); #1; perf_clr = 0;
        load_test(SER);
        pulse_start;
        load_test(SER + 1);
        for (t = SER; t < TESTS; t = t + 1) begin
            wait_done;
            if (t + 1 < TESTS) begin
                pulse_start;
                fork
                    read_check(t);
                    if (t + 2 < TESTS) load_test(t + 2);
                join
            end else begin
                @(posedge clk); #1;
                read_check(t);
            end
        end
        perf_sel = 0; #1; cyc_total = perf_data;
        perf_sel = 3; #1; mm        = perf_data;

        // N, PEs, latency(start->done), cycles/product (x100), MACs/cycle (x100), errors, checks
        $display("SCALING,%0d,%0d,%0d,%0d,%0d,%0d,%0d", N, NN, lat,
                 100*cyc_total / mm, 100*mm*N*N*N / cyc_total, errors, checks);
        if (errors == 0) $display(" RESULT: N=%0d PASSED (%0d element checks)", N, checks);
        else             $display(" RESULT: N=%0d FAILED (%0d / %0d)", N, errors, checks);
        $finish;
    end

endmodule
