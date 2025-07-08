module arbiter #(
    parameter  ACCESS_QUEUE_L = 1
)(
    input   logic           clk,
    input   logic           rst,

    //I-cache access port
    input   logic [31:0]    dfp_addr_i,
    input   logic           dfp_read_i,
    input   logic           dfp_write_i,
    input   logic [255:0]   dfp_wdata_i,
    output  logic [255:0]   dfp_rdata_i,
    output  logic           dfp_resp_i,
    
    //D-cache access port
    input   logic [31:0]    dfp_addr_d,
    input   logic           dfp_read_d,
    input   logic           dfp_write_d,
    input   logic [255:0]   dfp_wdata_d,
    output  logic [255:0]   dfp_rdata_d,
    output  logic           dfp_resp_d,

    output  logic   [31:0]  bmem_addr,
    output  logic           bmem_read,
    output  logic           bmem_write,
    output  logic   [63:0]  bmem_wdata,
    input   logic           bmem_ready,
    // input   logic   [31:0]  bmem_raddr,
    input   logic   [63:0]  bmem_rdata,
    input   logic           bmem_rvalid
);

    logic   [31:0]  ufp_addr;
    logic           ufp_read;
    logic           ufp_write;
    logic   [255:0] ufp_rdata;
    logic   [255:0] ufp_wdata;
    logic           ufp_resp;

    logic i_active, d_active, d_busy, i_busy;

    assign i_active = dfp_write_i || dfp_read_i;
    assign d_active = dfp_write_d || dfp_read_d;

    dram_adapter dram_adapter(
        .*
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            i_busy <= '0;
            d_busy <= '0;
        end
        else begin 
            if (i_active && !d_busy) i_busy <= '1;
            else if (!i_active) i_busy <= '0;

            if (!i_active && !i_busy && d_active) d_busy<='1;
            else if (!d_active) d_busy <= '0;

        end
    end


    always_comb begin
        if (bmem_ready) begin
            unique casez({i_active && !d_busy, d_active})
                2'b1? : begin
                    ufp_addr    = dfp_addr_i;
                    ufp_read    = dfp_read_i;
                    ufp_write   = dfp_write_i;
                    ufp_wdata   = dfp_wdata_i;
                    dfp_rdata_i = ufp_rdata;
                    dfp_resp_i  = ufp_resp;
                    dfp_rdata_d = 'x;
                    dfp_resp_d  = '0;
                end
                2'b01 : begin
                    ufp_addr    = dfp_addr_d;
                    ufp_read    = dfp_read_d;
                    ufp_write   = dfp_write_d;
                    ufp_wdata   = dfp_wdata_d;
                    dfp_rdata_d = ufp_rdata;
                    dfp_resp_d  = ufp_resp;
                    dfp_rdata_i = 'x;
                    dfp_resp_i  = '0;
                end
                2'b00 : begin
                    ufp_addr    = 'x;
                    ufp_read    = '0;
                    ufp_write   = '0;
                    ufp_wdata   = 'x;
                    dfp_rdata_i = 'x;
                    dfp_resp_i  = '0;
                    dfp_rdata_d = 'x;
                    dfp_resp_d  = '0;
                end  
            endcase
        end else begin
            ufp_addr    = 'x;
            ufp_read    = '0;
            ufp_write   = '0;
            ufp_wdata   = 'x;
            dfp_rdata_i = 'x;
            dfp_resp_i  = '0;
            dfp_rdata_d = 'x;
            dfp_resp_d  = '0;
        end

    end

endmodule : arbiter