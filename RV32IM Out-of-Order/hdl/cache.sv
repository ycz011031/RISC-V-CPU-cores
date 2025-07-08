module cache (
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic           ufp_rmask,
    output  logic   [255:0] ufp_rdata,
    output  logic           ufp_resp,
    output  logic           ufp_miss,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp
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

    logic cache_en;


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
            .clk0       (clk & cache_en),
            .csb0       (csb_all),
            .web0       (web_tag[i]),
            .addr0      (addr_all),
            .din0       (din_tag),
            .dout0      (dout_tag[i])
        );
        sp_ff_array valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (csb_all),
            .web0       (web_valid[i]),
            .addr0      (addr_all),
            .din0       (din_valid),
            .dout0      (dout_valid[i])
        );
    end endgenerate

    sp_ff_array #(
        .WIDTH      (3)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       (csb_all || !cache_en),
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
    logic        rmask_reg;
    logic [3:0]  wmask_reg;
    logic [31:0] wdata_reg;

    logic [7:0] cur_state;

    localparam idle      = 8'b00000001;
    localparam hit       = 8'b00000010;
    localparam allocate  = 8'b00000100;
    localparam writeback = 8'b00001000;
    
    assign ufp_tag = addr_reg[31:9];

    assign cache_en = !((cur_state == 8'b00000001) && (ufp_rmask == '0) || !dfp_resp && cur_state == 8'b00000100);
    assign addr_all = ((ufp_rmask == '0)|| cur_state != idle)? addr_reg[8:5] : ufp_addr[8:5];
    //assigning tag_hit signal
    //assigning activation flags
    always_comb begin
        if (dout_tag[0] == ufp_tag && dout_valid[0] == '1) tag_hit = 4'b0001;
        else if (dout_tag[1] == ufp_tag && dout_valid[1] == '1) tag_hit = 4'b0010;
        else if (dout_tag[2] == ufp_tag && dout_valid[2] == '1) tag_hit = 4'b0100;
        else if (dout_tag[3] == ufp_tag && dout_valid[3] == '1) tag_hit = 4'b1000;
        else tag_hit = '0;

        if (rmask_reg != '0) rd_flag = '1;
        else rd_flag = '0;
    end


    always_ff @(posedge clk) begin
        if (rst) begin
            cur_state <= idle;
            target_web<= '0;
        end else begin
            unique case (cur_state)
                idle : begin
                    if (ufp_rmask) begin
                        addr_reg   <= ufp_addr;
                        rmask_reg  <= ufp_rmask;
                        cur_state  <= hit;
                    end
                end
                hit : begin
                    if (|(tag_hit)) cur_state <= idle;
                    else cur_state <= allocate;
                    
                    unique casez (dout_lru)
                        3'b?00 : target_web <= 4'b0001;
                        3'b?10 : target_web <= 4'b0010;
                        3'b0?1 : target_web <= 4'b0100;
                        3'b1?1 : target_web <= 4'b1000;
                        default: target_web <= 4'b0001;
                    endcase                   

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
        ufp_miss = '0;
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
            end
            hit : begin
                if (|(tag_hit))begin
                        // ufp interface
                        unique case (tag_hit)
                            4'b0001 : begin
                                ufp_rdata = dout_data[0];
                            end
                            4'b0010 : begin
                                ufp_rdata = dout_data[1];
                            end
                            4'b0100 : begin
                                ufp_rdata = dout_data[2];
                            end
                            4'b1000 : begin
                                ufp_rdata = dout_data[3];
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
                end
            end
            allocate : begin
                ufp_miss  = '1;
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
                    web_lru    = '1;
                    din_lru    = '1;
                end else begin
                    web_data    = '1;
                    wmask_data  = '1;
                    din_data    = '0;
                    web_tag     = '1;
                    din_tag     = '0;
                    web_valid   = '1;
                    din_valid   = '0;
                    web_lru     = '1;
                    din_lru     = '0;
                end
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
            end
        endcase
    end
    

endmodule