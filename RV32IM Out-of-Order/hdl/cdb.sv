module cdb
import rv32i_types::*;
(
    input   logic              clk,
    input   logic              rst,
    input   logic              flush,

    input   CDB_t              alu1_cdb,
    input   CDB_t              alu2_cdb,
    input   CDB_t              mul_cdb,
    input   CDB_t              div_cdb,
    input   CDB_t              lui_cdb,
    input   CDB_t              st_cdb,
    input   CDB_t              ld_cdb,
    input   CDB_t              br_cdb,

    output  CDB_t              out_cdb_1,
    output  CDB_t              out_cdb_2,
    output  logic              alu1_cdb_rdy,
    output  logic              alu2_cdb_rdy,
    output  logic              mul_cdb_rdy,
    output  logic              div_cdb_rdy,
    output  logic              lui_cdb_rdy,
    output  logic              st_cdb_rdy,
    output  logic              ld_cdb_rdy,
    output  logic              br_cdb_rdy,


    input   rvfi_entry         rvfi_entry_alu1,
    input   rvfi_entry         rvfi_entry_alu2,
    input   rvfi_entry         rvfi_entry_mul,
    input   rvfi_entry         rvfi_entry_div,
    input   rvfi_entry         rvfi_entry_lui,
    input   rvfi_entry         rvfi_entry_st,
    input   rvfi_entry         rvfi_entry_ld,
    input   rvfi_entry         rvfi_entry_br,
    output  rvfi_entry         rvfi_entry_cdb_reg_1,
    output  rvfi_entry         rvfi_entry_cdb_reg_2
);



always_ff @ (posedge clk) begin
    if(rst || flush)begin
        out_cdb_1.valid <='0;
        out_cdb_2.valid <='0;
        rvfi_entry_cdb_reg_1 <= '0;
        rvfi_entry_cdb_reg_2 <= '0;
    end else begin
        if(ld_cdb.valid)begin
            out_cdb_1            <= ld_cdb;
            rvfi_entry_cdb_reg_1 <= rvfi_entry_ld;
        end else if (mul_cdb.valid)begin
            out_cdb_1            <= mul_cdb;
            rvfi_entry_cdb_reg_1 <= rvfi_entry_mul;
        end else if(lui_cdb.valid)begin
            out_cdb_1            <= lui_cdb;
            rvfi_entry_cdb_reg_1 <= rvfi_entry_lui;
        end else if (alu1_cdb.valid)begin
            out_cdb_1            <= alu1_cdb;
            rvfi_entry_cdb_reg_1 <= rvfi_entry_alu1;
        end else begin
            out_cdb_1.valid            <= '0;
            rvfi_entry_cdb_reg_1 <= '0;
        end

        if (br_cdb.valid)begin
            out_cdb_2            <= br_cdb;
            rvfi_entry_cdb_reg_2 <= rvfi_entry_br;
        end else if (st_cdb.valid)begin
            out_cdb_2            <= st_cdb;
            rvfi_entry_cdb_reg_2 <= rvfi_entry_st;
        end else if (div_cdb.valid)begin
            out_cdb_2            <= div_cdb;
            rvfi_entry_cdb_reg_2 <= rvfi_entry_div;
        end else if (alu2_cdb.valid)begin
            out_cdb_2            <= alu2_cdb;
            rvfi_entry_cdb_reg_2 <= rvfi_entry_alu2;
        end else begin
            out_cdb_2.valid            <= '0;
            rvfi_entry_cdb_reg_2 <= '0;
        end   
    end
end

always_comb begin
    unique casez ({alu1_cdb.valid, lui_cdb.valid, mul_cdb.valid, ld_cdb.valid})
        4'b???1: begin
            alu1_cdb_rdy = '0;
            lui_cdb_rdy  = '0;
            mul_cdb_rdy   = '0;
            ld_cdb_rdy   = '1;
        end
        4'b??10: begin
            alu1_cdb_rdy = '0;
            lui_cdb_rdy  = '0;
            mul_cdb_rdy   = '1;
            ld_cdb_rdy   = '1;
        end
        4'b?100: begin
            alu1_cdb_rdy = '0;
            lui_cdb_rdy  = '1;
            mul_cdb_rdy   = '1;
            ld_cdb_rdy   = '1;
        end        
        default: begin
            alu1_cdb_rdy = '1;
            lui_cdb_rdy  = '1;
            mul_cdb_rdy   = '1;
            ld_cdb_rdy   = '1;           
        end
    endcase

    unique casez ({alu2_cdb.valid, div_cdb.valid, st_cdb.valid, br_cdb.valid})
        4'b???1: begin
            alu2_cdb_rdy  = '0;
            div_cdb_rdy = '0;
            st_cdb_rdy  = '0;
            br_cdb_rdy   = '1;
        end
        4'b??10: begin
            alu2_cdb_rdy  = '0;
            div_cdb_rdy = '0;
            st_cdb_rdy  = '1;
            br_cdb_rdy   = '1;
        end
        4'b?100: begin
            alu2_cdb_rdy  = '0;
            div_cdb_rdy = '1;
            st_cdb_rdy  = '1;
            br_cdb_rdy   = '1;
        end    
        default: begin
            alu2_cdb_rdy  = '1;
            div_cdb_rdy = '1;
            st_cdb_rdy  = '1;
            br_cdb_rdy   = '1;           
        end
    endcase
end

endmodule