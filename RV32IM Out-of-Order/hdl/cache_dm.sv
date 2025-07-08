module cache_dm (
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]   ufp_addr,
    input   logic            ufp_rmask,
    output  logic   [255:0]  ufp_rdata,
    output  logic            ufp_resp,
    output  logic            ufp_miss,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]   dfp_addr,
    output  logic            dfp_read,
    output  logic            dfp_write,
    input   logic   [255:0]  dfp_rdata,
    output  logic   [255:0]  dfp_wdata,
    input   logic            dfp_resp
);

    //General Purpose interface signal
    logic       csb_all;
    logic [5:0] addr_all;

    // data_array interface
    logic          web_data;
    logic [31:0]   wmask_data;
    logic [255:0]  din_data;
    logic [255:0]  dout_data;

    // tag_array interface
    logic          web_tag;
    logic [20:0]   din_tag;
    logic [20:0]   dout_tag;

    // valid_array interface
    logic          web_valid;
    logic          din_valid;
    logic          dout_valid;

    logic cache_en;
    
    

    dm_cache_data_array data_array (
        .clk0       (clk & cache_en),
        .csb0       (csb_all),
        .web0       (web_data),
        .wmask0     (wmask_data),
        .addr0      (addr_all),
        .din0       (din_data),
        .dout0      (dout_data)
    );
    dm_cache_tag_array tag_array (
        .clk0       (clk & cache_en),
        .csb0       (csb_all),
        .web0       (web_tag),
        .addr0      (addr_all),
        .din0       (din_tag),
        .dout0      (dout_tag)
    );
    sp_ff_array #(
        .S_INDEX(6)
    )valid_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       (csb_all || !cache_en),
        .web0       (web_valid),
        .addr0      (addr_all),
        .din0       (din_valid),
        .dout0      (dout_valid)
    );



    logic[20:0] ufp_tag;
    logic       tag_hit;
    logic       rd_flag;
    logic       wr_flag;


    logic [31:0] addr_reg;
    logic        rmask_reg;
    logic [31:0] wdata_reg;

    logic [7:0] cur_state;

    localparam idle      = 8'b00000001;
    localparam hit       = 8'b00000010;
    localparam allocate  = 8'b00000100;
    localparam writeback = 8'b00001000;

    assign cache_en = !((cur_state == 8'b00000001) && (ufp_rmask == '0) || !dfp_resp && cur_state == 8'b00000100);
    
    
    assign ufp_tag = addr_reg[31:11];
    assign addr_all = ((ufp_rmask == '0)|| cur_state != idle)? addr_reg[10:5] : ufp_addr[10:5];

    //assigning tag_hit signal
    //assigning activation flags
    always_comb begin
        if (dout_tag == ufp_tag && dout_valid == '1) tag_hit = 1'b1;
        else tag_hit = '0;

        if (rmask_reg != '0) rd_flag = '1;
        else rd_flag = '0;        
    end


    always_ff @(posedge clk) begin
        if (rst) begin
            cur_state <= idle;
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
            end
            hit : begin
                if (|(tag_hit))begin                        
                    ufp_rdata = dout_data;
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
                end else begin
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
                    web_data   = '0;
                    wmask_data = '1;
                    din_data   = dfp_rdata;
                    web_tag    = '0;
                    din_tag    = addr_reg[31:11];
                    web_valid  = '0;
                    din_valid  = '1;
                end else begin
                    web_data    = '1;
                    wmask_data  = '1;
                    din_data    = '0;
                    web_tag     = '1;
                    din_tag     = '0;
                    web_valid   = '1;
                    din_valid   = '0;
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
            end
        endcase
    end
    

endmodule