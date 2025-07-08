module arbiter_pro 
import rv32i_types::*;
#(
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
    //input   logic           bmem_ready,
    input   logic   [31:0]  bmem_raddr,
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

    dfp_word_t i_reg, d_reg, p_reg;
    logic write_en;
    logic pf_complete;
    logic         pf_hit;

    always_ff @(posedge clk) begin
        if (rst) begin
            i_busy <= '0;
            d_busy <= '0;
            i_reg.valid <= '0;
            d_reg.valid <= '0;
            p_reg.valid <= '0;
            i_reg.addr  <= '0;
        end
        else begin

            if (dfp_resp_i) i_reg.valid <= '0;
            else if (i_active && !pf_hit) begin
                i_reg.valid <= '1;
                i_reg.addr  <= dfp_addr_i;
                i_reg.read  <= dfp_read_i;
                i_reg.write <= dfp_write_i;
                i_reg.wdata <= dfp_wdata_i;
            end

            if (dfp_resp_d) d_reg.valid <= '0;
            else if (d_active) begin
                d_reg.valid <= '1;
                d_reg.addr  <= dfp_addr_d;
                d_reg.read  <= dfp_read_d;
                d_reg.write <= dfp_write_d;
                d_reg.wdata <= dfp_wdata_d;
            end

            if (pf_complete) p_reg.valid <= '0;
            else if (dfp_resp_i) begin
                p_reg.valid <= '1;
                p_reg.addr  <= {(dfp_addr_i[31:5]+1'b1),5'd0};
                p_reg.read  <= '1;
            end
        end
    end

    logic [255:0] pf_reg;
    logic [31:0]  pf_addr;
    logic         pf_valid;


    assign pf_hit = pf_valid && (pf_addr == dfp_addr_i);
    
    logic [1:0] pointer1,pointer2;
    logic       r_active, w_active, r_complete;

    logic       r_1, r_2, r_3 ,w_1, w_2;
    assign r_1 = i_reg.read && i_reg.valid;
    assign r_2 = d_reg.read && d_reg.valid;
    assign r_3 = p_reg.read && p_reg.valid;
    assign w_1 = i_reg.write && i_reg.valid;
    assign w_2 = d_reg.write && d_reg.valid;

    logic r_1_done, r_2_done, r_3_done, w_1_done, w_2_done;
    logic r_1_wait, r_2_wait, r_3_wait;
    logic w_sel, r_sel;
    logic [31:0] dfp_raddr_reg;
    logic addr_sel1, addr_sel2;

    


    assign ufp_wdata = d_reg.wdata;
    assign write_en  = w_2;

    assign bmem_read =  r_active && !w_2;
    assign bmem_write = w_2;
    assign bmem_wdata = ufp_wdata[pointer2*64+:64];
    assign bmem_addr  = w_2? d_reg.addr : addr_sel1 ? d_reg.addr : addr_sel2? p_reg.addr : i_reg.addr;


    assign dfp_rdata_i = pf_hit ? pf_reg : ufp_rdata;
    assign dfp_rdata_d = ufp_rdata;  
    assign r_1_done = (dfp_raddr_reg == i_reg.addr )? r_complete : '0;
    assign r_2_done = (dfp_raddr_reg == d_reg.addr )? r_complete : '0;
    assign r_3_done = (dfp_raddr_reg == p_reg.addr )? r_complete : '0;
    assign dfp_resp_i  = (r_1_done && r_1) || pf_hit;
    assign dfp_resp_d  = (r_2_done && r_2) || (w_2 && ((pointer2[0] && pointer2[1])));
    assign pf_complete = r_3_done && r_3;


always_ff @(posedge clk) begin
    if (rst) begin
        pf_valid <= '0;
        pf_addr  <= '0;
    end else begin
        if (pf_complete) begin
            pf_reg <= ufp_rdata;
            pf_addr <= dfp_raddr_reg;
        end
    end
end



always_ff @(posedge clk) begin
    if (rst) begin
        r_active <= '0;
        w_active <= '0;
        r_complete <= '0;
        pointer1 <= '0;
        pointer2 <= '0;
        r_1_wait <= '0;
        r_2_wait <= '0;
        r_3_wait <= '0;
        addr_sel1 <= '0;
        addr_sel2 <= '0;
    end else begin
        if (!w_2 && r_1 && !r_1_wait && !r_1_done) begin
            r_active <= '1;
            r_1_wait <= '1;
            addr_sel1 <= '0;
            addr_sel2 <= '0; 
        end else 
        if (!w_2 && r_2 && !r_2_wait && !r_2_done) begin
            r_active <= '1;
            r_2_wait <= '1;
            addr_sel1 <= '1;
        end else 
        if (!w_2 && r_3 && !r_3_wait && !r_3_done) begin
            r_active <= '1;
            r_3_wait <= '1;
            addr_sel1 <= '0;
            addr_sel2 <= '1;
        end else if (!w_2)r_active <='0;

        if (r_1_done)r_1_wait <= '0;
        if (r_2_done)r_2_wait <= '0;
        if (r_3_done)r_3_wait <= '0;

        if (bmem_rvalid) begin
            dfp_raddr_reg <= bmem_raddr;
            pointer1 <= pointer1 + 2'd1;
            ufp_rdata[pointer1*64 +:64] <= bmem_rdata;
            if (pointer1 == 2'b11) begin
                r_complete <= '1;
            end
        end

        if (pointer1 == 2'b00) r_complete <= '0;
        if (pointer2 == 2'b11) w_active <= '0;


        if (write_en) begin
            pointer2 <= pointer2 + 2'd1;
        end
    end
end

endmodule : arbiter_pro