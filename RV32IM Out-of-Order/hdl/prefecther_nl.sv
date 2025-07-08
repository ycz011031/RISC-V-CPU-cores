module prefechter_nl #(
    parameter  ACCESS_QUEUE_L = 1
)(
    input   logic           clk,
    input   logic           rst,
    input   logic           flush,

    //I-cache access port
    input   logic   [31:0]  ufp_addr_i,
    input   logic   [3:0]   ufp_rmask_i,
    output  logic   [255:0] ufp_rdata_i,
    output  logic           ufp_resp_i,

    
    //D-cache access port
    output  logic   [31:0]  ufp_addr_o,
    output  logic           ufp_rmask_o,
    input  logic            ufp_miss,
    input  logic    [255:0] ufp_rdata_o,
    input  logic            ufp_resp_o
);

    logic   [31:0]  next_addr;
    logic           latch;
    logic           resp_latch;
    logic           miss_latch;
    logic           prefechter_active;
    logic           active_reg;
    assign prefechter_active = miss_latch && resp_latch && !(&ufp_rmask_i);
 
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            next_addr  <= '0;
            latch      <= '0;
            resp_latch <= '0;
            miss_latch <= '0;
            active_reg <= '0;
        end
        else begin 
            if (ufp_rmask_i != '0) begin
                next_addr <= {(ufp_addr_i[31:5] + 1'b1),5'd0};
                latch     <= '1;
            end else if (latch == '1) latch <= '0;

            if (ufp_resp_o) resp_latch <= '1;
            else resp_latch <= '0;

            if (ufp_miss) miss_latch <= '1;
            else if (resp_latch && miss_latch) miss_latch <='0;
            active_reg <= prefechter_active;
        end
    end

    always_comb begin
        ufp_resp_i   <= ufp_resp_o && !active_reg;
        ufp_rdata_i  <= ufp_rdata_o;
        case (resp_latch && miss_latch && !(&(ufp_rmask_i)))
            1'b0 : begin
                ufp_addr_o   <= ufp_addr_i;
                ufp_rmask_o  <= &(ufp_rmask_i);
                
            end
            default : begin
                ufp_addr_o   <= next_addr;
                ufp_rmask_o  <= latch;
                // ufp_addr_o   <= ufp_addr_i;
                // ufp_rmask_o  <= &(ufp_rmask_i);
            end
        endcase
    end

endmodule : prefechter_nl