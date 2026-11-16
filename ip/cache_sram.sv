// ============================================================================
// cache_sram : single-port synchronous SRAM used by pcache
// ============================================================================
//
// Port behaviour (identical to the OpenRAM 1rw models in */sram/output):
//   * csb = 0 at a clock edge registers the address; with web = 0 the bytes
//     selected by wmask are written.
//   * dout = mem[registered address], valid the cycle after the access and
//     held while csb = 1.
//
// Default: a behavioural array (vendor neutral; Vivado infers block or
// distributed RAM from it).
// `define USE_OPENRAM_SRAM : the geometries that have an OpenRAM macro use the
// macro instead (the Synopsys flow; macros come from <core>/sram/output).
// ============================================================================

module cache_sram #(
    parameter int DEPTH = 16,
    parameter int WIDTH = 256,
    parameter int NMASK = 32        // write-enable granules (WIDTH % NMASK == 0)
)(
    input   logic                       clk,
    input   logic                       csb,    // active-low chip select
    input   logic                       web,    // active-low write enable
    input   logic   [NMASK-1:0]         wmask,
    input   logic   [$clog2(DEPTH)-1:0] addr,
    input   logic   [WIDTH-1:0]         din,
    output  logic   [WIDTH-1:0]         dout
);

    localparam int GW = WIDTH / NMASK;

`ifdef USE_OPENRAM_SRAM
    localparam bit MACRO = (DEPTH == 16 && WIDTH == 256 && NMASK == 32) ||
                           (DEPTH == 16 && WIDTH == 23)                 ||
                           (DEPTH == 64 && WIDTH == 256 && NMASK == 32) ||
                           (DEPTH == 64 && WIDTH == 21);
`else
    localparam bit MACRO = 1'b0;
`endif

    generate
`ifdef USE_OPENRAM_SRAM
        if (DEPTH == 16 && WIDTH == 256 && NMASK == 32) begin : m_mp_data
            mp_cache_data_array u (.clk0(clk), .csb0(csb), .web0(web), .wmask0(wmask),
                                   .addr0(addr), .din0(din), .dout0(dout));
        end else if (DEPTH == 16 && WIDTH == 23) begin : m_mp_tag
            mp_cache_tag_array u (.clk0(clk), .csb0(csb), .web0(web),
                                  .addr0(addr), .din0(din), .dout0(dout));
        end else if (DEPTH == 64 && WIDTH == 256 && NMASK == 32) begin : m_dm_data
            dm_cache_data_array u (.clk0(clk), .csb0(csb), .web0(web), .wmask0(wmask),
                                   .addr0(addr), .din0(din), .dout0(dout));
        end else if (DEPTH == 64 && WIDTH == 21) begin : m_dm_tag
            dm_cache_tag_array u (.clk0(clk), .csb0(csb), .web0(web),
                                  .addr0(addr), .din0(din), .dout0(dout));
        end
`endif
        if (!MACRO) begin : behav
            logic [WIDTH-1:0]           mem [DEPTH];
            logic [$clog2(DEPTH)-1:0]   addr_q;
            logic [WIDTH-1:0]           bitmask;

            always_comb begin
                for (int i = 0; i < NMASK; i++) bitmask[i*GW +: GW] = {GW{wmask[i]}};
            end

            // whole-word write of the merged value (no part-select NBA into
            // an unpacked array: xsim drops some of those)
            always_ff @(posedge clk) begin
                if (!csb) begin
                    addr_q <= addr;
                    if (!web) mem[addr] <= (mem[addr] & ~bitmask) | (din & bitmask);
                end
            end

            assign dout = mem[addr_q];
        end
    endgenerate

endmodule : cache_sram
