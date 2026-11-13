module dram_adapter(
    input   logic           clk,
    input   logic           rst,

    input   logic   [31:0]  ufp_addr,
    input   logic           ufp_read,
    input   logic           ufp_write,
    output  logic   [255:0] ufp_rdata,
    input   logic   [255:0] ufp_wdata,
    output  logic           ufp_resp,

    output  logic   [31:0]  bmem_addr,
    output  logic           bmem_read,
    output  logic           bmem_write,
    output  logic   [63:0]  bmem_wdata,
    // input   logic           bmem_ready,
    // input   logic   [31:0]  bmem_raddr,
    input   logic   [63:0]  bmem_rdata,
    input   logic           bmem_rvalid
);


logic [1:0] pointer;
logic       r_active, w_active, r_complete;
// logic   dummy;
// assign dummy = bmem_ready;

always_comb begin
    bmem_read = !r_active && ufp_read && !r_complete;
    bmem_write = ufp_write;
    bmem_wdata = ufp_wdata[pointer*64+:64];
    bmem_addr  = ufp_addr;

    ufp_resp = r_complete || (w_active && (pointer[0] && pointer[1]));


end



always_ff @(posedge clk) begin
    if (rst) begin
        r_active <= '0;
        w_active <= '0;
        r_complete <= '0;
        pointer <= '0;
    end else begin
        if (ufp_read && !r_active && !r_complete)  r_active <= '1;
        if (ufp_write && !w_active) w_active <= '1;

        if (bmem_rvalid) begin
            pointer <= pointer + 2'd1;
            ufp_rdata[pointer*64 +:64] <= bmem_rdata;
            if (pointer == 2'b11) begin
                r_active <= '0;
                r_complete <= '1;
            end
        end
        if (pointer == 2'b00) r_complete <= '0;
        if (pointer == 2'b11) w_active <= '0;


        if (ufp_write && !bmem_rvalid) begin

            pointer <= pointer + 2'd1;
        end
    end
end




endmodule : dram_adapter


            

            

        