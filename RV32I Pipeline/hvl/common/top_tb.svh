    longint timeout;
    initial begin
        $value$plusargs("TIMEOUT_ECE411=%d", timeout);
    end

    // same banked DRAM model as the out-of-order core
    mem_itf_banked mem_itf(.*);
    `ifdef ECE411_MAGIC_MEM
        magic_dram_w_burst mem(.itf(mem_itf));              // no DRAM timing
    `else
        dram_w_burst_frfcfs_controller mem(.itf(mem_itf));
    `endif

    mon_itf mon_itf(.*);
    monitor monitor(.itf(mon_itf));

    `ifdef ECE411_PERF
        perf_probe perf_probe(.itf(mon_itf));   // cycle accounting -> ./perf.json
    `endif

    cpu dut(
        .clk            (clk),
        .rst            (rst),

        .bmem_addr      (mem_itf.addr  ),
        .bmem_read      (mem_itf.read  ),
        .bmem_write     (mem_itf.write ),
        .bmem_wdata     (mem_itf.wdata ),
        .bmem_ready     (mem_itf.ready ),
        .bmem_raddr     (mem_itf.raddr ),
        .bmem_rdata     (mem_itf.rdata ),
        .bmem_rvalid    (mem_itf.rvalid)
    );

    `include "rvfi_reference.svh"

    always @(posedge clk) begin
        if (mon_itf.halt) begin
            $finish;
        end
        if (timeout == 0) begin
            $error("TB Error: Timed out");
            $fatal;
        end
        if (mem_itf.error != 0 || mon_itf.error != 0) begin
            $fatal;
        end
        timeout <= timeout - 1;
    end
