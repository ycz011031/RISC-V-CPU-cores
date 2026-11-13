// ============================================================================
// cpu : pipeline core + arbiter + shared 2 KB direct-mapped cache + DRAM
// ============================================================================
//
//   core --imem--+
//                +--> arbiter --> cache_shared --> dram_adapter --> bmem (DRAM)
//   core --dmem--+    (D first)   (DM, write-back)  (32 B line <-> 4 x 64 b bursts)
//
// Top-level ports are the same banked-memory interface as the out-of-order
// core, so both cores run on the same testbench memory model.
// ============================================================================

module cpu
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    output  logic   [31:0]  bmem_addr,
    output  logic           bmem_read,
    output  logic           bmem_write,
    output  logic   [63:0]  bmem_wdata,
    input   logic           bmem_ready,
    input   logic   [31:0]  bmem_raddr,
    input   logic   [63:0]  bmem_rdata,
    input   logic           bmem_rvalid
);

    mem_req_t       imem_req, dmem_req, cache_req;
    mem_rsp_t       imem_rsp, dmem_rsp, cache_rsp;
    logic           cache_src, cache_rsp_src;
    rvfi_entry      rvfi;                       // hvl/common/rvfi_reference.json

    logic   [31:0]  dfp_addr;
    logic           dfp_read, dfp_write, dfp_resp;
    logic   [255:0] dfp_rdata, dfp_wdata;

    core core (
        .clk        (clk),
        .rst        (rst),
        .imem_req   (imem_req),
        .imem_rsp   (imem_rsp),
        .dmem_req   (dmem_req),
        .dmem_rsp   (dmem_rsp),
        .rvfi       (rvfi)
    );

    arbiter arbiter (
        .i_req      (imem_req),
        .i_rsp      (imem_rsp),
        .d_req      (dmem_req),
        .d_rsp      (dmem_rsp),
        .c_req      (cache_req),
        .c_src      (cache_src),
        .c_rsp      (cache_rsp),
        .c_rsp_src  (cache_rsp_src)
    );

    cache_shared cache (
        .clk         (clk),
        .rst         (rst),
        .ufp_req     (cache_req),
        .ufp_src     (cache_src),
        .ufp_rsp     (cache_rsp),
        .ufp_rsp_src (cache_rsp_src),
        .dfp_addr    (dfp_addr),
        .dfp_read    (dfp_read),
        .dfp_write   (dfp_write),
        .dfp_rdata   (dfp_rdata),
        .dfp_wdata   (dfp_wdata),
        .dfp_resp    (dfp_resp)
    );

    // ported unchanged from the out-of-order core
    dram_adapter dram_adapter (
        .clk         (clk),
        .rst         (rst),
        .ufp_addr    (dfp_addr),
        .ufp_read    (dfp_read),
        .ufp_write   (dfp_write),
        .ufp_rdata   (dfp_rdata),
        .ufp_wdata   (dfp_wdata),
        .ufp_resp    (dfp_resp),
        .bmem_addr   (bmem_addr),
        .bmem_read   (bmem_read),
        .bmem_write  (bmem_write),
        .bmem_wdata  (bmem_wdata),
        .bmem_rdata  (bmem_rdata),
        .bmem_rvalid (bmem_rvalid)
    );

    // one outstanding line request at a time: bmem_ready / bmem_raddr unused
    // (same as the OoO core's dram_adapter)

endmodule : cpu
