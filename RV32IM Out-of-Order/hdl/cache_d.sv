module cache_d (
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic   [3:0]   ufp_rmask,
    input   logic   [3:0]   ufp_wmask,
    output  logic   [31:0]  ufp_rdata,
    input   logic   [31:0]  ufp_wdata,
    output  logic           ufp_resp,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp,

    input   logic           d_cache_en
);

    //General Purpose interface signal
    logic       csb_all;
    logic [3:0] addr_all;
    

    // data_array interface
    logic [3:0]    web_data;
    logic [31:0]   wmask_data;
    logic [255:0]  din_data;
    logic [255:0]  dout_data [4];

    // tag_array interface
    logic [3:0]    web_tag;
    logic [22:0]   din_tag;
    logic [22:0]   dout_tag [4];

    // valid_array interface
    logic [3:0]    web_valid;
    logic          din_valid;
    logic [3:0]    dout_valid;

    //  lru_array interface
    logic          web_lru;
    logic [2:0]    din_lru;
    logic [2:0]    dout_lru;

    // dirty_array interface
    logic [3:0]     web_dirty;
    logic           din_dirty;
    logic [3:0]     dout_dirty;
    logic           cache_en;
    logic           tag_en;

    logic debug_tag_en;
    assign debug_tag_en = cache_en && !(d_cache_en||tag_en);


    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk & cache_en),
            .csb0       (csb_all),
            .web0       (web_data[i]),
            .wmask0     (wmask_data),
            .addr0      (addr_all),
            .din0       (din_data),
            .dout0      (dout_data[i])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk & (d_cache_en|tag_en)),
            .csb0       (csb_all),
            .web0       (web_tag[i]),
            .addr0      (addr_all),
            .din0       (din_tag),
            .dout0      (dout_tag[i])
        );
        sp_ff_array valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (csb_all|| !cache_en),
            .web0       (web_valid[i]),
            .addr0      (addr_all),
            .din0       (din_valid),
            .dout0      (dout_valid[i])
        );

            sp_ff_array dirty_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (csb_all|| !cache_en),
            .web0       (web_dirty[i]),
            .addr0      (addr_all),
            .din0       (din_dirty),
            .dout0      (dout_dirty[i])
        );
    end endgenerate

    sp_ff_array #(
        .WIDTH      (3)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       (csb_all|| !cache_en),
        .web0       (web_lru),
        .addr0      (addr_all),
        .din0       (din_lru),
        .dout0      (dout_lru)
    );


    logic[22:0] ufp_tag;
    logic[3:0]  tag_hit;
    logic       active_flag;
    logic       rd_flag;
    logic       wr_flag;
    logic       dirty_flag;
    logic[3:0]  target_web;

    logic [31:0] addr_reg;
    logic [3:0]  rmask_reg;
    logic [3:0]  wmask_reg;
    logic [31:0] wdata_reg;

    logic [7:0] cur_state;
    logic  power_tracker;
    logic [22:0]   dout_tag_reg [4];

    localparam idle      = 8'b00000001;
    localparam hit       = 8'b00000010;
    localparam allocate  = 8'b00000100;
    localparam writeback = 8'b00001000;
    
    assign ufp_tag = addr_reg[31:9];
    assign addr_all = ((ufp_rmask == '0 && ufp_wmask == '0 )|| cur_state != idle)? addr_reg[8:5] : ufp_addr[8:5];
    assign cache_en = !(!dfp_resp && cur_state == 8'b00000100 || cur_state == 8'b00001000 || (ufp_rmask == '0 && ufp_wmask == '0 && cur_state == 8'b00000001));
    assign tag_en = !(!dfp_resp && cur_state == 8'b00000100 || cur_state == 8'b00001000);
    assign power_tracker = cur_state == 8'b00000100;

    //assigning tag_hit signal
    //assigning activation flags
    always_comb begin

        if (dout_tag[0] == ufp_tag && dout_valid[0] == '1) tag_hit = 4'b0001;
        else if (dout_tag[1] == ufp_tag && dout_valid[1] == '1) tag_hit = 4'b0010;
        else if (dout_tag[2] == ufp_tag && dout_valid[2] == '1) tag_hit = 4'b0100;
        else if (dout_tag[3] == ufp_tag && dout_valid[3] == '1) tag_hit = 4'b1000;
        else tag_hit = '0;



        if (ufp_rmask != '0 || ufp_wmask != '0) active_flag = '1;
        else active_flag = '0;

        if (rmask_reg != '0) rd_flag = '1;
        else rd_flag = '0;

        if (wmask_reg != '0) wr_flag = '1;
        else wr_flag = '0;

        //if (dout_valid != 4'b1111) dirty_flag = '0;
        //else begin
        unique casez (dout_lru)
            3'b?00 : dirty_flag = dout_dirty[0] & dout_valid[0];
            3'b?10 : dirty_flag = dout_dirty[1] & dout_valid[1];
            3'b0?1 : dirty_flag = dout_dirty[2] & dout_valid[2];
            3'b1?1 : dirty_flag = dout_dirty[3] & dout_valid[3];
            default: dirty_flag = '0;
        endcase
        //end
    end


    always_ff @(posedge clk) begin
        if (rst) begin
            cur_state <= idle;
            target_web<= '0;
        end else begin
            unique case (cur_state)
                idle : begin
                    if (active_flag) begin
                        addr_reg   <= ufp_addr;
                        rmask_reg  <= ufp_rmask;
                        wmask_reg  <= ufp_wmask;
                        wdata_reg  <= ufp_wdata;
                        cur_state  <= hit;
                    end
                end
                hit : begin
                    if (|(tag_hit)) cur_state <= idle;
                    else if (dirty_flag) begin
                        cur_state <= writeback;
                        dout_tag_reg <= dout_tag;
                    end
                    else cur_state <= allocate;
                    
                    unique casez (dout_lru)
                        3'b?00 : target_web <= 4'b0001;
                        3'b?10 : target_web <= 4'b0010;
                        3'b0?1 : target_web <= 4'b0100;
                        3'b1?1 : target_web <= 4'b1000;
                        default: target_web <= 4'b0001;
                    endcase                   

                end

                writeback : begin
                    if (dfp_resp) cur_state <= allocate;
                    else cur_state <= writeback;
                end

                allocate : begin
                    if (dfp_resp) cur_state <= idle;
                    else cur_state <= allocate;
                end

                default : begin
                    cur_state <= idle;
                end
            endcase
        end
    end

    always_comb begin
        unique case (cur_state)
            idle : begin
                // ufp interface
                ufp_rdata = '0;
                ufp_resp  = '0;

                //dfp interface
                dfp_addr  = '0;
                dfp_read  = '0;
                dfp_write = '0;
                dfp_wdata = '0;

                //internal signals
                csb_all  = '0;

                web_data  = '1;
                wmask_data= '0;
                din_data  = '0;

                web_tag   = '1;
                din_tag   = '0;

                web_valid = '1;
                din_valid = '0;

                web_lru   = '1;
                din_lru   = '0;

                web_dirty = '1;
                din_dirty = '0;
            end
            hit : begin
                if (|(tag_hit))begin
                    if (rd_flag) begin
                        // ufp interface
                        unique case (tag_hit)
                            4'b0001 : begin
                                ufp_rdata[7:0]   = ~rmask_reg[0]? '0 : dout_data[0][addr_reg[4:0]*8+:8];
                                ufp_rdata[15:8]  = ~rmask_reg[1]? '0 : dout_data[0][(addr_reg[4:0]+1)*8+:8];
                                ufp_rdata[23:16] = ~rmask_reg[2]? '0 : dout_data[0][(addr_reg[4:0]+2)*8+:8];
                                ufp_rdata[31:24] = ~rmask_reg[3]? '0 : dout_data[0][(addr_reg[4:0]+3)*8+:8];
                            end
                            4'b0010 : begin
                                ufp_rdata[7:0]   = ~rmask_reg[0]? '0 : dout_data[1][addr_reg[4:0]*8+:8];
                                ufp_rdata[15:8]  = ~rmask_reg[1]? '0 : dout_data[1][(addr_reg[4:0]+1)*8+:8];
                                ufp_rdata[23:16] = ~rmask_reg[2]? '0 : dout_data[1][(addr_reg[4:0]+2)*8+:8];
                                ufp_rdata[31:24] = ~rmask_reg[3]? '0 : dout_data[1][(addr_reg[4:0]+3)*8+:8];
                            end
                            4'b0100 : begin
                                ufp_rdata[7:0]   = ~rmask_reg[0]? '0 : dout_data[2][addr_reg[4:0]*8+:8];
                                ufp_rdata[15:8]  = ~rmask_reg[1]? '0 : dout_data[2][(addr_reg[4:0]+1)*8+:8];
                                ufp_rdata[23:16] = ~rmask_reg[2]? '0 : dout_data[2][(addr_reg[4:0]+2)*8+:8];
                                ufp_rdata[31:24] = ~rmask_reg[3]? '0 : dout_data[2][(addr_reg[4:0]+3)*8+:8];
                            end
                            4'b1000 : begin
                                ufp_rdata[7:0]   = ~rmask_reg[0]? '0 : dout_data[3][addr_reg[4:0]*8+:8];
                                ufp_rdata[15:8]  = ~rmask_reg[1]? '0 : dout_data[3][(addr_reg[4:0]+1)*8+:8];
                                ufp_rdata[23:16] = ~rmask_reg[2]? '0 : dout_data[3][(addr_reg[4:0]+2)*8+:8];
                                ufp_rdata[31:24] = ~rmask_reg[3]? '0 : dout_data[3][(addr_reg[4:0]+3)*8+:8];
                            end
                            default : ufp_rdata = '0;
                        endcase
                        ufp_resp  = '1;

                        //dfp interface
                        dfp_addr  = '0;
                        dfp_read  = '0;
                        dfp_write = '0;
                        dfp_wdata = '0;

                        //internal signals
                        csb_all   = '0;
                        
                        web_data  = '1;
                        wmask_data= '0;
                        din_data  = '0;

                        web_tag   = '1;
                        din_tag   = '0;

                        web_valid = '1;
                        din_valid = '0;


                        web_lru   = '0;
                        unique case (tag_hit)
                            4'b0001 : din_lru = {dout_lru[2],2'b11};
                            4'b0010 : din_lru = {dout_lru[2],2'b01};
                            4'b0100 : din_lru = {1'b1,dout_lru[1],1'b0};
                            4'b1000 : din_lru = {1'b0,dout_lru[1],1'b0};
                            default : din_lru = '0;
                        endcase

                        web_dirty = '1;
                        din_dirty = '0;
                    end else begin
                        ufp_rdata = '0;
                        ufp_resp  = '1;

                        //dfp interface
                        dfp_addr  = '0;
                        dfp_read  = '0;
                        dfp_write = '0;
                        dfp_wdata = '0;

                        //internal signals
                        csb_all   = '0;
                        
                        unique case (tag_hit)
                            4'b0001 : web_data = 4'b1110;
                            4'b0010 : web_data = 4'b1101;
                            4'b0100 : web_data = 4'b1011;
                            4'b1000 : web_data = 4'b0111;
                            default : web_data = '0;
                        endcase
                        // May require inversion
                        wmask_data= '0;
                        wmask_data[addr_reg[4:0]+:4]=wmask_reg;
                        din_data  = '0;
                        din_data[addr_reg[4:2]*32+:32] = wdata_reg;
                        
                        web_tag   = '1;
                        din_tag   = '0;

                        web_valid = '1;
                        din_valid = '0;

                        web_lru   = '0;
                        unique case (tag_hit)
                            4'b0001 : din_lru = {dout_lru[2],2'b11};
                            4'b0010 : din_lru = {dout_lru[2],2'b01};
                            4'b0100 : din_lru = {1'b1,dout_lru[1],1'b0};
                            4'b1000 : din_lru = {1'b0,dout_lru[1],1'b0};
                            default : din_lru = '0;
                        endcase

                        unique case (tag_hit)
                            4'b0001 : web_dirty = 4'b1110;
                            4'b0010 : web_dirty = 4'b1101;
                            4'b0100 : web_dirty = 4'b1011;
                            4'b1000 : web_dirty = 4'b0111;
                            default : web_dirty = '0;
                        endcase                      
                        din_dirty = '1;
                    end
                end
                else begin
                    ufp_rdata = '0;
                    ufp_resp  = '0;

                    //dfp interface
                    dfp_addr  = '0;
                    dfp_read  = '0;
                    dfp_write = '0;
                    dfp_wdata = '0;

                    //internal signals
                    csb_all   = '0;
                    
                    web_data  = '1;
                    wmask_data= '0;
                    din_data  = '0;

                    web_tag   = '1;
                    din_tag   = '0;

                    web_valid = '1;
                    din_valid = '0;

                    web_lru   = '1;
                    din_lru   = '0;

                    web_dirty = '1;
                    din_dirty = '0;
                end
            end

            allocate : begin
                ufp_rdata = '0;
                ufp_resp  = '0;

                dfp_read  = '1;
                dfp_addr  = {addr_reg[31:5],5'b00000};
                dfp_write = '0;
                dfp_wdata = '0;

                csb_all   = '0;
                if (dfp_resp) begin
                    web_data   = ~target_web;
                    wmask_data = '1;
                    din_data   = dfp_rdata;

                    web_tag    = ~target_web;
                    din_tag    = addr_reg[31:9];

                    web_valid  = ~target_web;
                    din_valid  = '1;

                    web_dirty  = ~target_web;
                    din_dirty  = '0;

                    web_lru    = '1;
                    din_lru    = '0;
                end else begin
                    web_data    = '1;
                    wmask_data  = '1;
                    din_data    = '0;

                    web_tag     = '1;
                    din_tag     = '0;

                    web_valid   = '1;
                    din_valid   = '0;

                    web_dirty   = '1;
                    din_dirty   = '0;

                    web_lru     = '1;
                    din_lru     = '0;
                end
            end

            writeback : begin
                ufp_rdata  ='0;
                ufp_resp   ='0;
                unique case (target_web)
                    4'b0001 : dfp_addr = {dout_tag_reg[0],addr_reg[8:5],5'b00000};
                    4'b0010 : dfp_addr = {dout_tag_reg[1],addr_reg[8:5],5'b00000};
                    4'b0100 : dfp_addr = {dout_tag_reg[2],addr_reg[8:5],5'b00000};
                    4'b1000 : dfp_addr = {dout_tag_reg[3],addr_reg[8:5],5'b00000};
                    default : dfp_addr = '0;
                endcase
                dfp_read   = '0;
                dfp_write  = '1;
                unique case (target_web)
                    4'b0001: dfp_wdata = dout_data[0];
                    4'b0010: dfp_wdata = dout_data[1];
                    4'b0100: dfp_wdata = dout_data[2];
                    4'b1000: dfp_wdata = dout_data[3];
                    default: dfp_wdata = '0;
                endcase

                csb_all ='0;

                web_data  = '1;
                wmask_data= '0;
                din_data  = '0;

                web_tag   = '1;
                din_tag   = '0;

                web_valid = '1;
                din_valid = '0;

                web_lru   = '1;
                din_lru   = '0;

                web_dirty = '1;
                din_dirty = '0;
            end

            default : begin
                // ufp interface
                ufp_rdata = '0;
                ufp_resp  = '0;

                //dfp interface
                dfp_addr  = '0;
                dfp_read  = '0;
                dfp_write = '0;
                dfp_wdata = '0;

                //internal signals
                csb_all   = '1;
                
                web_data  = '1;
                wmask_data= '0;
                din_data  = '0;

                web_tag   = '1;
                din_tag   = '0;

                web_valid = '1;
                din_valid = '0;

                web_lru   = '1;
                din_lru   = '0;

                web_dirty = '1;
                din_dirty = '0;
            end
        endcase
    end
    

endmodule