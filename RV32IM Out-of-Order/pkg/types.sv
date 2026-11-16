/////////////////////////////////////////////////////////////
// Maybe merge what is in mp_verif/pkg/types.sv over here? //
/////////////////////////////////////////////////////////////

package rv32i_types;

    localparam INST_TYPE_L = 3;
`ifdef OOO_WIN_BITS
    localparam PADDR_L = `OOO_WIN_BITS;       // experiment: ROB and rename buffer size
    localparam ROBADDR_L = `OOO_WIN_BITS;
`else
    localparam PADDR_L = 6;                     // 64-entry rename buffer
    localparam ROBADDR_L = 6;                   // 64-entry ROB
`endif
`ifdef OOO_PHT_BITS
    localparam PHT_ADDR_L = `OOO_PHT_BITS;
`else
    localparam PHT_ADDR_L = 12;                 // 4096-entry gshare table, 12-bit history
`endif
    localparam FTQ_DEPTH = 16;
`ifdef OOO_MEM_DEPTH
    localparam MEM_DEPTH = `OOO_MEM_DEPTH;   // must match cpu.sv MEM_DEPTH
`else
    localparam MEM_DEPTH = 4;
`endif

    localparam FTQ_ADDR_L = $clog2(FTQ_DEPTH);

    typedef enum logic [6:0] {
        op_b_lui       = 7'b0110111, // load upper immediate (U type)
        op_b_auipc     = 7'b0010111, // add upper immediate PC (U type)
        op_b_jal       = 7'b1101111, // jump and link (J type)
        op_b_jalr      = 7'b1100111, // jump and link register (I type)
        op_b_br        = 7'b1100011, // branch (B type)
        op_b_load      = 7'b0000011, // load (I type)
        op_b_store     = 7'b0100011, // store (S type)
        op_b_imm       = 7'b0010011, // arith ops with register/immediate operands (I type)
        op_b_reg       = 7'b0110011  // arith ops with register operands (R type)
    } rv32i_opcode;

    typedef enum logic[2:0] {
        rv32m_f3_mul   = 3'b000,
        rv32m_f3_mulh  = 3'b001,
        rv32m_f3_mulhsu= 3'b010,
        rv32m_f3_mulhu = 3'b011,
        rv32m_f3_div   = 3'b100,
        rv32m_f3_divu  = 3'b101,
        rv32m_f3_rem   = 3'b110,
        rv32m_f3_remu  = 3'b111
    } rv32m_func3_t;
    
    typedef enum logic [2:0] {
        arith_f3_add   = 3'b000, // check logic 30 for sub if op_reg op
        arith_f3_sll   = 3'b001,
        arith_f3_slt   = 3'b010,
        arith_f3_sltu  = 3'b011,
        arith_f3_xor   = 3'b100,
        arith_f3_sr    = 3'b101, // check logic 30 for logical/arithmetic
        arith_f3_or    = 3'b110,
        arith_f3_and   = 3'b111
    } arith_f3_t;

    typedef enum logic [2:0] {
        load_f3_lb     = 3'b000,
        load_f3_lh     = 3'b001,
        load_f3_lw     = 3'b010,
        load_f3_lbu    = 3'b100,
        load_f3_lhu    = 3'b101
    } load_f3_t;

    typedef enum logic [2:0] {
        store_f3_sb    = 3'b000,
        store_f3_sh    = 3'b001,
        store_f3_sw    = 3'b010
    } store_f3_t;

    typedef enum logic [2:0] {
        branch_f3_beq  = 3'b000,
        branch_f3_bne  = 3'b001,
        branch_f3_blt  = 3'b100,
        branch_f3_bge  = 3'b101,
        branch_f3_bltu = 3'b110,
        branch_f3_bgeu = 3'b111
    } branch_f3_t;

    typedef enum logic [2:0] {
        alu_op_add     = 3'b000,
        alu_op_sll     = 3'b001,
        alu_op_sra     = 3'b010,
        alu_op_sub     = 3'b011,
        alu_op_xor     = 3'b100,
        alu_op_srl     = 3'b101,
        alu_op_or      = 3'b110,
        alu_op_and     = 3'b111
    } alu_ops;

    typedef enum logic [6:0] {
        base           = 7'b0000000,
        variant        = 7'b0100000
    } funct7_t;

    typedef enum logic {
        set_inst = 1'b0,
        alu_inst  = 1'b1
    } set_inst_sel_t;

    // more mux def here
    typedef enum logic {
        pc_plus = 1'b0,
        branch  = 1'b1
    } pc_sel_t;

    typedef enum logic {
        alu_result = 1'b0,
        mem_out  = 1'b1
    } wb_sel_t;

    typedef enum logic {
        use_rs2 = 1'b0,
        use_imm  = 1'b1
    } alu_b_sel_t;

    typedef struct packed {
        set_inst_sel_t set_inst_sel;
        // pc_sel_t pc_sel;
        wb_sel_t wb_sel;
        // alu_b_sel_t alu_b_sel;
        logic use_rs1, use_rs2;
        logic isload, isstore;
        logic isbranch, isjal, isjalr;
        logic br_taken;
        
    } ctrl_word_t;

    typedef struct packed {
        logic        valid;
        logic [31:0] addr;
        logic        read;
        logic        write;
        logic [255:0]wdata;
    }dfp_word_t;

    typedef enum logic [1:0] {
        snt = 2'b00,
        wnt = 2'b01,
        wt = 2'b10,
        st = 2'b11
    } saturating_counter_t;

    typedef struct packed {
        logic   [31:0]      inst;
        logic   [31:0]      pc;
        logic   [31:0]      pc_next;
        logic   [63:0]      order;

        logic               i_valid;
        logic               br_pred;

        logic [FTQ_ADDR_L-1:0] ftq_addr;

    } if_id_stage_reg_t;

    typedef struct packed {
        logic   [31:0]      inst;        
        logic   [31:0]      pc;
        logic   [63:0]      order;
        logic   [6:0]       opcode;
        logic   [31:0]      rs1_data, rs2_data, imm;
        logic   [4:0]       rd_addr, rs1_addr, rs2_addr;
        logic               i_valid; 
        logic   [4:0]       op_type;
        logic   [2:0]       cmpop;
        logic               rs1_renamed, rs2_renamed;
        logic [PADDR_L-1:0] rd_paddr, rs1_paddr, rs2_paddr;

        logic regf_we;
        logic               br_pred;

        ctrl_word_t ctrl_word;

        logic [FTQ_ADDR_L-1:0] ftq_addr;

    } id_dis_stage_reg_t;

    typedef struct packed {
        logic valid;
        logic [INST_TYPE_L-1:0]  inst_type;
        logic [4:0] rd_aaddr;
        logic [PADDR_L-1:0] rd_paddr;

        logic br_pred;
        
    } disp_rob_t;

    typedef struct packed {
        logic [PADDR_L-1:0] rd_paddr;
        logic [ROBADDR_L-1:0] rob_addr;
        logic [31:0]    rd_data;
        logic regf_we;
        logic valid;

        logic br_mispred;
        logic br_only_taken;
        logic [31:0] br_target;

        logic [FTQ_ADDR_L-1:0] ftq_addr;

        
    } CDB_t;

    
    //TODO add order

    typedef struct packed {
        logic [ROBADDR_L-1:0] rob_addr;
        logic                 rs1_use;
        logic                 rs1_valid;
        logic [PADDR_L-1:0]     rs1_paddr;
        logic [31:0]          rs1_data;
        logic                 rs2_use;
        logic                 rs2_valid;
        logic [PADDR_L-1:0]     rs2_paddr;
        logic [31:0]          rs2_data;
        logic [PADDR_L-1:0]   rd_paddr;
        logic                 regf_we;
        logic [31:0]          imm;
        logic [63:0]          order;
        logic [4:0]           op_type; // func7[5], func3

        logic                 br_pred;
        logic [FTQ_ADDR_L-1:0] ftq_addr;

    } RS_entry_t;


    typedef struct packed {
        logic   [ROBADDR_L-1:0] rob_addr;
        logic   [PADDR_L-1:0]   rd_paddr;
        logic   [63:0]          order;
        logic   [2:0]           mem_op;
        logic   [31:0]          mem_addr;
        logic   [3:0]           mem_rmask;
        logic   [MEM_DEPTH-1:0] depend_idx;
    } load_entry_t;

    typedef struct packed {
        logic   [ROBADDR_L-1:0] rob_addr;
        logic   [63:0]          order;
        logic   [2:0]           mem_op;
        logic   [31:0]          mem_addr;
        logic   [3:0]           mem_wmask;
        logic   [31:0]          mem_wdata;      // the store's register value (unshifted: placed in its
                                                // byte lanes by store_wdata() when the store drains)
        logic                   data_valid;     // store data present (it may arrive after the address)
        logic   [PADDR_L-1:0]   data_paddr;     // physical register the data comes from while !data_valid
    } store_entry_t;

    typedef struct packed {
        logic valid;
        logic status;
        logic [INST_TYPE_L-1:0] inst_type;

        logic [PADDR_L-1:0] rd_paddr;
        logic [4:0]    rd_aaddr;

        logic br_mispred;
        // logic br_addr_mispred;

        // logic [31:0] br_target;

    } rob_entry_t;

    typedef struct packed {
        logic          valid;
        logic [63:0]   order;
        logic [31:0]   inst;
        logic [4:0]    rs1_addr;
        logic [4:0]    rs2_addr;
        logic [31:0]   rs1_rdata;
        logic [31:0]   rs2_rdata;
        logic [4:0]    rd_addr;
        logic [31:0]   rd_wdata;
        logic [31:0]   pc_rdata;
        logic [31:0]   pc_wdata;
        logic [31:0]   mem_addr;
        logic [3:0]    mem_rmask;
        logic [3:0]    mem_wmask;
        logic [31:0]   mem_rdata;
        logic [31:0]   mem_wdata;

        logic [31:0]   br_imm;
    } rvfi_entry;

    typedef struct packed {
        // logic [31:0]    pc;
        logic [31:0]    br_target;
        logic [PHT_ADDR_L-1:0]  pht_addr;
        logic [PHT_ADDR_L-1:0]  ghr;
        // logic [31:0]            func_ret;
        logic [1:0]                  commit_count;
        logic                        ras_push;     // jalr is a call  (RAS repair at commit)
        logic                        ras_pop;      // jalr is a return
    } ftq_entry_t;

    typedef struct packed {
        logic [31:0] ret_addr;
    } ras_entry_t;


    typedef union packed {
        logic [31:0] word;

        struct packed {
            logic [11:0] i_imm;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  rd;
            rv32i_opcode opcode;
        } i_type;

        struct packed {
            logic [6:0]  funct7;
            logic [4:0]  rs2;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  rd;
            rv32i_opcode opcode;
        } r_type;

        struct packed {
            logic [11:5] imm_s_top;
            logic [4:0]  rs2;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  imm_s_bot;
            rv32i_opcode opcode;
        } s_type;


        struct packed {
         // Fill this out to get branches running!
            // logic [12|10:5] imm_b_top;
            logic imm_b_top12;
            logic [10:5] imm_b_top105;
            logic [4:0]  rs2;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            // logic [4:1|11]  imm_b_bot;
            logic [4:1] imm_b_bot41;
            logic imm_b_bot11;
            rv32i_opcode opcode;
        } b_type;

        struct packed {
            logic [31:12] imm;
            logic [4:0]   rd;
            rv32i_opcode  opcode;
        } j_type;

    } instr_t;

    // store data placed in its byte lanes (wmask carries the address offset)
    // fetch: which candidate pc_next is (if_stage -> line buffer parallel tag compare)
typedef enum logic [2:0] {NX_PC, NX_FLUSH, NX_FLUSH_REG, NX_BR, NX_PC4, NX_T2, NX_PC8} nx_sel_t;

function automatic logic [31:0] store_wdata(input logic [2:0] op, input logic [3:0] wmask, input logic [31:0] v);
        logic [31:0] w;
        w = '0;
        unique case (op)
            store_f3_sb: begin
                if      (wmask[3]) w[31:24] = v[7:0];
                else if (wmask[2]) w[23:16] = v[7:0];
                else if (wmask[1]) w[15:8]  = v[7:0];
                else               w[7:0]   = v[7:0];
            end
            store_f3_sh: begin
                if (wmask[2]) w[31:16] = v[15:0];
                else          w[15:0]  = v[15:0];
            end
            store_f3_sw: w = v;
            default:     w = '0;
        endcase
        return w;
    endfunction

endpackage


