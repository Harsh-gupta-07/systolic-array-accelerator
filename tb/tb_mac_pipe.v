// =============================================================================
// File        : tb_mac_pipe.v
// Description : Compares the pipelined MAC (MUL_PIPE=1) against the
//               combinational MAC (MUL_PIPE=0) on the same random stimulus.
//   The pipelined accumulator must equal the reference accumulator delayed
//   by exactly one clock cycle, including clear and en=0 (hold) cycles.
// Run  : cd sim && make macpipe
// =============================================================================
`timescale 1ns / 1ps

module tb_mac_pipe;

    reg               clk, rst_n, clear, en;
    reg  signed [7:0] a, b;
    wire signed [31:0] acc0, acc1;
    reg  signed [31:0] acc0_d;     // reference delayed by one cycle
    integer cyc, errors = 0;

    mac_unit #(.MUL_PIPE(0)) u_ref  (.clk(clk), .rst_n(rst_n), .clear(clear), .en(en),
                                     .a(a), .b(b), .acc(acc0));
    mac_unit #(.MUL_PIPE(1)) u_pipe (.clk(clk), .rst_n(rst_n), .clear(clear), .en(en),
                                     .a(a), .b(b), .acc(acc1));

    initial clk = 0;
    always #5 clk = ~clk;

    always @(posedge clk) acc0_d <= acc0;

    initial begin
        $dumpfile("tb_mac_pipe.vcd");
        $dumpvars(0, tb_mac_pipe);
        $display("==================================================");
        $display(" tb_mac_pipe : MUL_PIPE=1 vs MUL_PIPE=0 (1-cycle shift)");
        $display("==================================================");
        rst_n = 0; clear = 0; en = 0; a = 0; b = 0;
        #22 rst_n = 1;
        @(posedge clk); #1;
        for (cyc = 0; cyc < 2000; cyc = cyc + 1) begin
            a     = $random;
            b     = $random;
            en    = ($random % 4) != 0;      // 75 % enabled
            clear = ($random % 37) == 0;     // occasional clear
            @(posedge clk); #1;
            if (cyc > 1 && acc1 !== acc0_d) begin
                errors = errors + 1;
                if (errors < 5) $display("  [FAIL] cycle %0d: pipe=%0d ref(delayed)=%0d",
                                         cyc, acc1, acc0_d);
            end
        end
        $display("  2000 random cycles compared (en/clear toggling)");
        $display("--------------------------------------------------");
        if (errors == 0) $display(" RESULT: PIPELINED MAC MATCHES REFERENCE (+1 cycle)");
        else             $display(" RESULT: PIPELINED MAC FAILED (%0d mismatches)", errors);
        $display("==================================================");
        $finish;
    end
endmodule
