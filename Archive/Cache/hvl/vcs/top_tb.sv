module top_tb;
    //---------------------------------------------------------------------------------
    // Waveform generation.
    //---------------------------------------------------------------------------------
    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, "+all");
    end

    //---------------------------------------------------------------------------------
    logic clk;
    logic rst;

    logic [31:0] ufp_addr;
    logic [3:0]  ufp_rmask;
    logic [3:0]  ufp_wmask;
    logic [31:0] ufp_rdata;
    logic [31:0] ufp_wdata;
    logic        ufp_resp;

    logic [31:0] dfp_addr;
    logic        dfp_read;
    logic        dfp_write;
    logic [255:0]dfp_rdata;
    logic [255:0]dfp_wdata;
    logic        dfp_resp;
    //---------------------------------------------------------------------------------

    //---------------------------------------------------------------------------------
    cache DUT(
        .clk(clk),
        .rst(rst),

        .ufp_addr(ufp_addr),
        .ufp_rmask(ufp_rmask),
        .ufp_wmask(ufp_wmask),
        .ufp_rdata(ufp_rdata),
        .ufp_wdata(ufp_wdata),
        .ufp_resp(ufp_resp),

        .dfp_addr(dfp_addr),
        .dfp_read(dfp_read),
        .dfp_write(dfp_write),
        .dfp_rdata(dfp_rdata),
        .dfp_wdata(dfp_wdata),
        .dfp_resp(dfp_resp)
    );
    //---------------------------------------------------------------------------------

    //---------------------------------------------------------------------------------
    int clock_half_period_ps = 1000;
    always #(clock_half_period_ps) clk = ~clk;
    //---------------------------------------------------------------------------------
    
    //mem_itf_w_mask #(mem_ift(.*));
    //simple_memory_256_wo_mask #(mem(.itf(mem_itf)));

    

    //---------------------------------------------------------------------------------
    // TODO: Verification constructs (recommended)
    //---------------------------------------------------------------------------------
    // Here's ASCII art of how the recommended testbench works:
    //                                +--------------+                           +-----------+
    //                       +------->| Golden model |---output_transaction_t--->|           |
    //                       |        +--------------+                           |           |
    //  input_transaction ---+                                                   | Check ==  |
    //                       |        +------+                                   |           |
    //                       +------->|  DUT |---output_transaction_t----------->|           |
    //                                +------+                                   +-----------+

    // Struct that defines an "input transaction" -- this is basically one
    // operation that's done on the cache.
    typedef struct packed {
        logic [31:0] address; // Address to read from.
        // Read or write? You could make an enum for this.
        // ... what else defines an input transaction? Think: rmask/wmask, data...
        bit transaction_type;
        bit [3:0] wmask;
        bit [3:0] rmask;
        bit [31:0] ufp_wdata;
        bit [255:0] dfp_wdata;
 
        // Note that it's useful to include the DFP signals here as well for
        // planned misses, like this:
        bit [255:0] dfp_rdata;
        // What else?
    } input_transaction_t;

    // The output transaction tells us how the cache is expected to behave due
    // to an input transaction.
    typedef struct packed {
        bit caused_writeback;
        bit caused_allocate;
        bit [31:0] dfp_addr;
        bit [31:0] returned_data;
        bit [255:0] dfp_writeback_data;

        // what else do you need?
    } output_transaction_t;

    logic [255:0] data_golden_arrays[4];
    // Similarly, make arrays for tags, valid, dirty, plru.

    function input_transaction_t generate_input_transaction();
        // This function generates an input transaction. 

        input_transaction_t inp;

        // Pick whether to generate a hit or miss.
        std::randomize (inp);
    endfunction : generate_input_transaction

    function output_transaction_t golden_cache_do(input_transaction_t inp);
        output_transaction_t out;
        // Do operations on the arrays, and fill up "out" correctly. Use "="
        // assignment here: this is not RTL. It is a behavioral software model 
        // of the cache.
    endfunction : golden_cache_do

    task drive_dut(input input_transaction_t inp, output output_transaction_t out);
        // Do inp operation on the DUT by driving with "<=".
        // Fill out an output_transaction_t struct while doing so depending on
        // what the DUT does. Refer to mp_verif to see how to drive and
        // monitor DUT signals. It may be useful to use fork...join, or to
        // also take as input the golden model's output struct to make it
        // easier to drive.
        

        // for (int i = 0; i<10; i++) begin

        //     generate_input_transaction()
        //     @(posedge clk)
        //     ufp_addr <= inp.ufp_addr;
        //     ufp_rmask<= transaction_type ? inp.rmask : '0 ;
        //     ufp_wmask<= transaction_type ? '0 : inp.wmask;
        //     returned_data <= ufp_rdata;
        //     ufp_wdata <= inp.ufp_wdata;
        //     ufp_resp;

        //     dfp_addr;
        //     dfp_read;
        //     dfp_write;
        //     dfp_rdata;
        //     dfp_wdata;
        //     dfp_resp;
        

    endtask : drive_dut

    function compare_outputs(output_transaction_t golden_out, output_transaction_t dut_out);
        // Compare the output structs, and $error() if there's a mismatch.
    endfunction : compare_outputs

    //---------------------------------------------------------------------------------
    // TODO: Main initial block that calls your tasks, then calls $finish

    initial begin
        clk = '0;

        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst = 1'b0;
    end

    logic [15:0] tb_counter = 16'd0;
    localparam endpoint = 16'd21;

    always @ (posedge clk iff !rst) begin
        if (ufp_resp == '1) begin
            tb_counter <= tb_counter + 1;
        end
        if (tb_counter == endpoint) $finish;

        if (dfp_read == '1 || dfp_write == '1) begin
            dfp_resp <= '1;
            dfp_rdata <= {208'b0,16'hECEB,dfp_addr};
        end else begin
            dfp_resp <= '0;
            dfp_rdata <= '0;
        end

    end

    always_comb begin
        unique case (tb_counter)
            16'd0 : begin
                ufp_addr  = 32'h000000000; // initial read request
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end
            16'd1 : begin
                ufp_addr  = 32'h00000001; // clean read hit
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end
            16'd2 : begin
                ufp_addr  = 32'h00000020; // same set, different line
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end 
            16'd3 : begin
                ufp_addr  = 32'h00000100; // clean write
                ufp_rmask = '0;
                ufp_wmask = '1;
                ufp_wdata = 32'h425425AA;
            end
            16'd4 : begin
                ufp_addr = 32'h00000120;
                ufp_rmask = '0;
                ufp_wmask = '1;
                ufp_wdata = 32'h462462AA;
            end
            16'd5 : begin
                ufp_addr  = 32'h00000100;
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end
            16'd6 : begin
                ufp_addr = 32'h00000200;
                ufp_rmask = '0;
                ufp_wmask = '1;
                ufp_wdata = 32'hEE416416;
            end
            16'd7 : begin
                ufp_addr = 32'h00000300;
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end
            16'd8 : begin
                ufp_addr = 32'h00000400;
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end
            16'd9 : begin
                ufp_addr = 32'h11000100;
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end

            // write back test
            16'd10 : begin
                ufp_addr = 32'h11000100;
                ufp_rmask = '0;
                ufp_wmask = '1;
                ufp_wdata = 32'hEE210210;
            end
            16'd11 : begin
                ufp_addr = 32'h12000100;
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end
            16'd12 : begin
                ufp_addr = 32'h13000100;
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end
            16'd13 : begin
                ufp_addr = 32'h14000100;
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end
            16'd14 : begin
                ufp_addr = 32'h15000100;
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end
            // PLRU test, 1<2<3<4<2<5 (EVICT 3)
            16'd15 : begin
                ufp_addr  = 32'h10000ff0;
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end
            16'd16 : begin
                ufp_addr = 32'h20000ff0;
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end
            16'd17 : begin
                ufp_addr = 32'h30000ff0;
                ufp_rmask = '0;
                ufp_wmask = '1;
                ufp_wdata = 32'hEE462462;
            end
            16'd18 : begin
                ufp_addr = 32'h40000ff0;
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end
            16'd19 : begin
                ufp_addr = 32'h20000ff0;
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end
            16'd20 : begin
                ufp_addr = 32'h50000ff0;
                ufp_rmask = '1;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end
                      




            default : begin
                ufp_addr  = '0;
                ufp_rmask = '0;
                ufp_wmask = '0;
                ufp_wdata = '0;
            end

        endcase
    end


    //---------------------------------------------------------------------------------

endmodule : top_tb
