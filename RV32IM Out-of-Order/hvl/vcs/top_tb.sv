module top_tb;

    timeunit 1ps;
    timeprecision 1ps;

    localparam WIDTH = 8;
    localparam DEPTH = 4;

    int clock_half_period_ps;
    initial begin
        $value$plusargs("CLOCK_PERIOD_PS_ECE411=%d", clock_half_period_ps);
        clock_half_period_ps = clock_half_period_ps / 2;
    end

    bit clk;
    always #(clock_half_period_ps) clk = ~clk;
    bit rst;

    initial begin
        $fsdbDumpfile("dump.fsdb");
        if ($test$plusargs("NO_DUMP_ALL_ECE411")) begin
            $fsdbDumpvars(0, dut, "+all");
            $fsdbDumpoff();
        end else begin
            $fsdbDumpvars(0, "+all");
        end
        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst <= 1'b0;
    end

    `include "top_tb.svh"

//     initial begin
//         $fsdbDumpfile("dump.fsdb");
//         $fsdbDumpvars(0, "+all");
//     end

//     //---------------------------------------------------------------------------------
//     // Declare cache port signals:
//     //---------------------------------------------------------------------------------

//     logic                   enq;
//     logic                   deq;
//     logic   [WIDTH-1:0]     din;

//     logic   [WIDTH-1:0]     dout;
//     logic                   full;
//     logic                   empty;

//     //---------------------------------------------------------------------------------
//     // Instantiate the DUT:
//     //---------------------------------------------------------------------------------

//     fifo #(
//         .WIDTH(WIDTH), 
//         .DEPTH(DEPTH)
//     ) dut (.*);

//     //---------------------------------------------------------------------------------
//     // Main initial block that calls your tasks, then calls $finish
//     //---------------------------------------------------------------------------------

//     initial begin
//         rst = 1'b1;
//         enq <= '0;
//         deq <= '0;
//         din <= '0;
//         repeat (2) @(posedge clk);
//         rst = 1'b0;

// ////////////enq testing/////////////

//         din <= 8'd1;
//         enq <= '1;
//         repeat (1) @(posedge clk);

//         din <= 8'd2;
//         repeat (1) @(posedge clk);

//         din <= 8'd3;
//         repeat (1) @(posedge clk);

//         din <= 8'd4;
//         repeat (1) @(posedge clk);

// ///////////enq on full////////////////////////

//         din <= 8'd5;
//         repeat (3) @(posedge clk);

// ///////////simultaneous enq and deq on full//////////////

//         din <= 8'd6;
//         enq <= '1;
//         deq <= '1;
//         repeat (3) @(posedge clk);

// ////////////deq testing/////////////////

//         enq <= '0;
//         deq <= '1;
//         repeat (2) @(posedge clk);

// /////////// simultaneous enq and deq on partially filled queue //////////////

//         din <= 8'd7;
//         enq <= '1;
//         deq <= '1;
//         repeat (3) @(posedge clk); 

// ////////////deq remaining 2 items/////////////////

//         enq <= '0;
//         deq <= '1;
//         repeat (2) @(posedge clk);

// ///////////deq testing on empty queue////////////

//         repeat (4) @(posedge clk);

// ///////////simultaneous enq and deq on empty//////////////

//         din <= 8'd8;
//         enq <= '1;
//         deq <= '1;
//         repeat (3) @(posedge clk);



//         $finish;

        

//     end

    

endmodule
