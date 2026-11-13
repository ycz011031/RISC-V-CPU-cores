module fetch
import rv32i_types::*;
(
    input   logic           clk,
    input   logic           rst,

    output  logic   [31:0]  imem_addr,
    output  logic   [3:0]   imem_rmask,
    input   logic   [31:0]  imem_rdata,
    input   logic           imem_resp,

    input   logic           mm_stall,
    // JALR data
    input   logic   [31:0]  jalr_target,
    input   logic           jalr_resolve,
    input   logic           br_flush,

    output  logic   [31:0]  inst,
    output  logic   [31:0]  PC_cur,
    output  logic   [31:0]  PC_next,
    output  logic   [31:0]  PC_cache,
    output  logic           fetch_rdy

);

logic [31:0] inst_cache;
logic        cache_flag;
logic        load_flag;
logic        branch_flag;
logic        jump_flag;
logic        jalr_flag_comb;
logic        jalr_flag_seq;
logic        br_flush_flag;
logic [4:0]  load_rd;
logic        mm_stall_reg;

logic [31:0] br_target;
logic [31:0] jal_target;
logic [31:0] br_source[5];
logic [31:0] dm_source[3];
logic        branch_latch;
logic        flush_latch;
logic        jalr_latch;
logic        lu_flag;


assign br_target = PC_cur + {{20{imem_rdata[31]}}, imem_rdata[7], imem_rdata[30:25], imem_rdata[11:8], 1'b0};
assign jal_target = PC_cur + {{12{imem_rdata[31]}}, imem_rdata[19:12], imem_rdata[20], imem_rdata[30:21], 1'b0};

// RV32M ops complete in the memory stage like loads (m_unit is the "memory"),
// so they get the same load-use bubble and the same stall-replay bookkeeping.
logic is_muldiv;
assign is_muldiv = (imem_rdata[6:0] == op_b_reg) && (imem_rdata[31:25] == muldiv);

always_comb begin
    if (imem_rdata[6:0]==op_b_jal && imem_resp)jump_flag = '1;
    else jump_flag = '0;
    if (imem_rdata[6:0]==op_b_br && imem_resp)branch_flag = '1;
    else branch_flag ='0;
    if (imem_rdata[6:0]==op_b_jalr && imem_resp)jalr_flag_comb = '1;
    else jalr_flag_comb = '0;
    if (fetch_rdy &&load_flag && (imem_rdata[19:15] == load_rd || imem_rdata[24:20] == load_rd))lu_flag = '1;  
    else lu_flag = '0;
end

always_ff @ (posedge clk) begin
    if (rst) begin
        PC_cur     <= 32'haaaaa000;
        PC_next    <= 32'haaaaa000+4;
        imem_rmask <= '1;
        inst       <= '0;
        fetch_rdy  <= '0;
        cache_flag <= '0;
        load_flag  <= '0;
        br_flush_flag <= '0;
        jalr_flag_seq <= '0;
        branch_latch  <= '0;
        mm_stall_reg  <= '0;
        flush_latch   <= '0;
        jalr_latch    <= '0;
    end else begin
        //BR_SOURCE CACHE ROTATION
        if (mm_stall) mm_stall_reg <= mm_stall;
        else if (imem_resp) mm_stall_reg <= '0;
        
        if (br_flush && !imem_resp) flush_latch<='1;
        else if (PC_cur == br_source[3])flush_latch <= '0;
        
        if (jalr_resolve) jalr_latch <='1;

        br_source[1]<=br_source[0];
        br_source[2]<=br_source[1];
        br_source[3]<=br_source[2];
        br_source[4]<=br_source[3];

                
        if (!mm_stall && !mm_stall_reg)begin
            dm_source[1] <= dm_source[0];
            dm_source[2] <= dm_source[1];
        end

        

        // imem interface and decode interface management
        // stall conditions
        if (mm_stall) begin
            fetch_rdy <= '0;
            branch_latch <= '0;
        end
        else if (flush_latch || jalr_latch||br_flush) begin
            fetch_rdy <= '0;
            branch_latch <= '0;
            jalr_flag_seq <= '0;
            if (!jalr_latch)begin
                jalr_latch <= '0;
            end
        end

        else if (jalr_flag_comb) begin
            fetch_rdy  <= '1;
            inst       <= imem_rdata;
            jalr_flag_seq <= '1;
        end
        else if (branch_latch)begin
            fetch_rdy <= '1;
            branch_latch <= '0;
        end
        else if ((imem_resp) && (PC_cur != dm_source[2])&&mm_stall_reg) fetch_rdy<='0;

        else if (jalr_flag_seq) begin
            if (jalr_resolve) begin
                jalr_flag_seq <= '0;
                fetch_rdy     <= '0;              
            end else begin
                fetch_rdy     <= '0;
            end
        end





        else begin
            imem_rmask <= '1;
            if (imem_resp) begin 
                if (! branch_latch) inst      <= imem_rdata;
                //Set Load flag & cache load destination
                if (imem_rdata[6:0] == op_b_load || is_muldiv) begin
                    load_flag <= '1;
                    load_rd   <= imem_rdata[11:7];
                end
                else load_flag <= '0;

                //if (branch_flag || jump_flag)branch_latch <= '1;

                // When Load flag high, check for hazard, if suspected, hold PC and drop ready
                if (lu_flag)begin
                    fetch_rdy <='0;
                end else
                if (branch_flag || jump_flag) begin   
                    branch_latch <= '1;                 
                    fetch_rdy <= '0;
                end 
                
                

                else begin
                    fetch_rdy <= '1; 
                    branch_latch <= '0;                   
                end                
            end else begin
                fetch_rdy <= '0;
                load_flag <= '0;
            end
        end

        if (imem_resp &&! branch_latch) PC_cache <= PC_cur; // for mispredict and SPIKE

        // PC and PC_cache management
        if (imem_resp)begin
        if (flush_latch)flush_latch <= '0;
        
        if (flush_latch||br_flush) begin
            PC_cur  <= br_source[2];
            PC_next <= br_source[2] + 4;
            
        end
        else
        if (mm_stall) begin
            PC_cur  <= dm_source[2];
            PC_next <= dm_source[2] + 4;
        end
        else if ((PC_cur != dm_source[2])&&mm_stall_reg) begin
            PC_cur <= dm_source[2];
            PC_next <= dm_source[2]+4;
        end
        else

        if (lu_flag)begin
            PC_cur    <= PC_cur;
            PC_next   <= PC_next;
        end
        else
        if (branch_flag && !branch_latch) begin
            PC_cur  <= br_target;
            PC_next <= br_target+4;
            br_source[0] <= PC_next;
        end
        else if (jump_flag && !branch_latch) begin
            PC_cur  <= jal_target;
            PC_next <= jal_target+4;
        end 
        else if (branch_latch) begin
            PC_cur <= PC_cur;
            PC_next <= PC_next;
        end
        else if (jalr_latch) begin
            PC_cur  <= jalr_target;
            PC_next <= jalr_target + 4;
            jalr_latch <= '0;
        end
        
        else if (jalr_flag_seq) begin
            PC_cur    <= PC_cur;
            PC_next   <= PC_next;
        end
        else if (imem_rdata[6:0] == op_b_store || imem_rdata[6:0] == op_b_load || is_muldiv) begin
            dm_source[0] <= PC_next;
            PC_cur       <= PC_next;
            PC_next      <= PC_next + 4; 
        end
        

        else begin
            PC_cur    <= PC_next;
            PC_next   <= PC_next + 4;
        end


        
    end
    end
end


always_comb begin
    if (mm_stall) begin
        imem_addr = dm_source[2];
    end else
    if (br_flush) imem_addr = br_source[2];
    else
    if (imem_resp && (PC_cur != dm_source[2])&&mm_stall_reg) imem_addr = dm_source[2];
    else
    if (imem_resp && (flush_latch))begin
        imem_addr = br_source[2];
    end 
    else if (imem_resp && jalr_latch) begin
        imem_addr = jalr_target;
    end
    
    else begin
    unique case (imem_resp)
        '1 : imem_addr = (mm_stall||branch_flag||jump_flag||flush_latch||lu_flag)? PC_cur:PC_next;
        '0 : imem_addr = PC_cur;
    endcase
    end
end
        
        







endmodule : fetch