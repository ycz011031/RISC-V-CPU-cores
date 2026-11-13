// Testbench top for Vivado xsim (and any simulator without VCS/Verdi FSDB).
// Same structure as hvl/vcs/top_tb.sv, minus the $fsdb* calls. Waveforms
// are recorded by xsim itself (run_xsim.py --wave writes a .wdb).
module top_tb;

    timeunit 1ps;
    timeprecision 1ps;

    int clock_half_period_ps;

    bit clk;
    bit rst;

    initial begin
        if (!$value$plusargs("CLOCK_PERIOD_PS_ECE411=%d", clock_half_period_ps)) begin
            clock_half_period_ps = 2000;
        end
        clock_half_period_ps = clock_half_period_ps / 2;
        forever #(clock_half_period_ps) clk = ~clk;
    end

    initial begin
        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst <= 1'b0;
    end

    `include "top_tb.svh"

endmodule
