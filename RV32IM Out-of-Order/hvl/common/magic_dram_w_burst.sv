// "Magic" banked memory: the same mem_itf_banked interface as
// dram_w_burst_frfcfs_controller, with no DRAM timing at all.
//
//   * ready is always high
//   * the first 64-bit beat of a read is returned in the cycle after the
//     request, followed by the other three beats (in request order)
//   * a write burst is committed when its 4th beat arrives
//
// This is the banked-interface counterpart of the old pipeline testbench's
// n_port_pipeline_memory_32_w_mask #(.MAGIC(1)). The cores' caches are still
// in the path, so cache misses still cost their fill handshake. The model
// counts line reads and writes so that cost can be seen.
//
// Selected in hvl/common/top_tb.svh with `define ECE411_MAGIC_MEM
// (tools/xsim/run_xsim.py --magic).
module magic_dram_w_burst (
    mem_itf_banked.mem itf
);

    string memfile;
    initial begin
        $value$plusargs("MEMLST_ECE411=%s", memfile);
    end

    // one entry per 32-byte line, same image format as the DRAM model
    logic [255:0] internal_memory_array [logic [26:0]];

    logic [31:0]  read_queue [$];
    int           read_beat;
    logic [255:0] write_buf;
    int           write_beat;
    logic [31:0]  write_addr;

    longint       line_reads, line_writes;

    function automatic logic [255:0] read_line(input logic [31:0] addr);
        if (internal_memory_array.exists(addr[31:5])) return internal_memory_array[addr[31:5]];
        else                                          return '0;
    endfunction

    assign itf.ready = 1'b1;

    always @(posedge itf.clk) begin
        if (itf.rst) begin
            internal_memory_array.delete();
            $readmemh(memfile, internal_memory_array);
            $display("using memory file %s (magic memory)", memfile);
            read_queue.delete();
            read_beat   = 0;
            write_beat  = 0;
            line_reads  = 0;
            line_writes = 0;
            itf.rvalid <= 1'b0;
            itf.rdata  <= 'x;
            itf.raddr  <= 'x;
        end else begin
            // writes: 4 consecutive beats, committed on the last one
            if (itf.write) begin
                if (write_beat == 0) write_addr = itf.addr;
                write_buf[64*write_beat +: 64] = itf.wdata;
                if (write_beat == 3) begin
                    internal_memory_array[write_addr[31:5]] = write_buf;
                    line_writes += 1;
                    write_beat = 0;
                end else begin
                    write_beat += 1;
                end
            end
            // reads: queue the request, stream beats starting next cycle
            if (itf.read) begin
                read_queue.push_back(itf.addr);
                line_reads += 1;
            end
            if (read_queue.size() != 0) begin
                automatic logic [255:0] line = read_line(read_queue[0]);
                itf.rvalid <= 1'b1;
                itf.raddr  <= read_queue[0];
                itf.rdata  <= line[64*read_beat +: 64];
                if (read_beat == 3) begin
                    read_beat = 0;
                    void'(read_queue.pop_front());
                end else begin
                    read_beat += 1;
                end
            end else begin
                itf.rvalid <= 1'b0;
                itf.rdata  <= 'x;
                itf.raddr  <= 'x;
            end
        end
    end

    // same protocol checks as the DRAM model
    always @(posedge itf.clk iff !itf.rst) begin
        if ($isunknown(itf.read) || $isunknown(itf.write)) begin
            $error("Memory Error: read/write is 1'bx");
            itf.error <= 1'b1;
        end
        if (itf.read && itf.write) begin
            $error("Memory Error: simultaneous read and write");
            itf.error <= 1'b1;
        end
        if (write_beat != 0 && !itf.write) begin
            $error("Memory Error: burst incomplete");
            itf.error <= 1'b1;
        end
        if ((itf.read || itf.write) && itf.addr[4:0] != '0) begin
            $error("Memory Error: address not aligned");
            itf.error <= 1'b1;
        end
    end

    final begin
        $display("Magic memory: %0d line reads, %0d line writes (cache fills / write-backs)",
                 line_reads, line_writes);
    end

endmodule
