// =============================================================================
// File        : systolic_controller_v2.v
// Project     : Systolic Array Matrix Multiplication Accelerator (CSA-222)
// Description : Phase II controller FSM.
//
//   Same five states as Phase I, with four additions:
//
//   1. Back-to-back runs : 'start' is accepted in IDLE *and* in DONE, so a
//                          new product begins the cycle after the previous
//                          one finishes (no idle bubble).
//   2. Accumulate mode   : if acc_mode = 1 when start is accepted, the CLEAR
//                          state is skipped and the PEs keep adding onto the
//                          previous result. Used for tiling large matrices
//                          (C_tile += A_tile(I,K) x B_tile(K,J)).
//   3. Bank swap         : 'swap' pulses when a run is accepted so the
//                          ping-pong buffer switches to the freshly loaded bank.
//   4. Result capture    : 'capture' (= DONE) copies the accumulators into the
//                          result buffer, so the host can read results while
//                          the next product is already being computed.
//
//   DRAIN lasts 2N-2+MUL_PIPE+BUF_REG cycles (one extra cycle for each
//   optional pipeline register: pipelined MAC, registered buffer output).
//
//      IDLE --start--> CLEAR --> FEED (N) --> DRAIN (2N-2+P) --> DONE
//        ^   \__start & acc_mode__________^                       |  |
//        |                                                         |  |
//        +-------------------- no start ---------------------------+  |
//                     start (& acc_mode ? FEED : CLEAR) <-------------+
// =============================================================================
`timescale 1ns / 1ps

module systolic_controller_v2 #(
    parameter N        = 4,
    parameter MUL_PIPE = 0,
    parameter BUF_REG  = 0,
    parameter KW       = (N > 1) ? $clog2(N) : 1
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire          acc_mode,   // 1 = do not clear (accumulate onto result)
    output reg           clear,
    output reg           en,
    output reg           feed,
    output reg  [KW-1:0] k_idx,
    output wire          swap,       // pulse: run accepted, switch buffer bank
    output reg           capture,    // pulse: copy accumulators to result buffer
    output reg           busy,
    output reg           done
);

    localparam [2:0] S_IDLE  = 3'd0,
                     S_CLEAR = 3'd1,
                     S_FEED  = 3'd2,
                     S_DRAIN = 3'd3,
                     S_DONE  = 3'd4;

    localparam integer DRAIN_CYC = ((N > 1) ? (2*N - 2) : 1) + MUL_PIPE + BUF_REG;
    localparam integer CW        = $clog2(DRAIN_CYC + 1);

    reg [2:0]    state, next_state;
    reg [CW-1:0] drain_cnt;

    wire can_start = (state == S_IDLE) || (state == S_DONE);
    wire accept    = can_start & start;
    assign swap    = accept;

    // ---------------- state register + counters ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            k_idx     <= {KW{1'b0}};
            drain_cnt <= {CW{1'b0}};
        end else begin
            state <= next_state;
            if (accept)
                k_idx <= {KW{1'b0}};
            else if (state == S_FEED)
                k_idx <= k_idx + 1'b1;

            if (state == S_FEED)
                drain_cnt <= {CW{1'b0}};
            else if (state == S_DRAIN)
                drain_cnt <= drain_cnt + 1'b1;
        end
    end

    // ---------------- next-state logic ----------------
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE : if (start) next_state = acc_mode ? S_FEED : S_CLEAR;
            S_CLEAR:            next_state = S_FEED;
            S_FEED : if (k_idx == N-1) next_state = S_DRAIN;
            S_DRAIN: if (drain_cnt == DRAIN_CYC-1) next_state = S_DONE;
            S_DONE : if (start) next_state = acc_mode ? S_FEED : S_CLEAR;
                     else       next_state = S_IDLE;
            default:            next_state = S_IDLE;
        endcase
    end

    // ---------------- Moore outputs ----------------
    always @(*) begin
        clear   = 1'b0;
        en      = 1'b0;
        feed    = 1'b0;
        busy    = 1'b1;
        done    = 1'b0;
        capture = 1'b0;
        case (state)
            S_IDLE : busy = 1'b0;
            S_CLEAR: clear = 1'b1;
            S_FEED : begin en = 1'b1; feed = 1'b1; end
            S_DRAIN: en = 1'b1;
            S_DONE : begin done = 1'b1; capture = 1'b1; busy = 1'b0; end
            default: busy = 1'b0;
        endcase
    end

endmodule
