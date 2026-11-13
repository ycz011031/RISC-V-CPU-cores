/////////////////////////////////////////////////////////////
// Maybe merge what is in mp_verif/pkg/types.sv over here? //
/////////////////////////////////////////////////////////////

package rv32i_types;

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
        variant        = 7'b0100000,
        muldiv         = 7'b0000001  // RV32M (opcode op_b_reg)
    } funct7_t;

    // RV32M funct3 (opcode op_b_reg, funct7 muldiv)
    typedef enum logic [2:0] {
        m_f3_mul       = 3'b000,
        m_f3_mulh      = 3'b001,
        m_f3_mulhsu    = 3'b010,
        m_f3_mulhu     = 3'b011,
        m_f3_div       = 3'b100,
        m_f3_divu      = 3'b101,
        m_f3_rem       = 3'b110,
        m_f3_remu      = 3'b111
    } m_f3_t;

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
            logic          b_12;
            logic [5:0]    imm_b_10_5;
            logic [4:0]    rs2;
            logic [4:0]    rs1;
            logic [2:0]    funct3;
            logic [4:1]    imm_b_4_1;
            logic          b_11;
            rv32i_opcode   opcode;
        } b_type;

        struct packed {
            logic [31:12] imm;
            logic [4:0]   rd;
            rv32i_opcode  opcode;
        } j_type;

    } instr_t;

    // ========================================================================
    // Memory-side interface (core <-> arbiter <-> shared cache)
    //
    // Hold-until-response protocol: a requester keeps presenting the same
    // request until `resp`. If it drops or changes the request before then,
    // the request is abandoned: a cache miss still fills the line, but no
    // response is ever returned for it. `raddr` tells the requester which
    // request a response belongs to (fetch uses it to drop wrong-path hits).
    // ========================================================================

    typedef struct packed {
        logic   [31:0]  addr;       // word aligned
        logic   [3:0]   rmask;
        logic   [3:0]   wmask;
        logic   [31:0]  wdata;
    } mem_req_t;

    typedef struct packed {
        logic           resp;
        logic   [31:0]  rdata;
        logic   [31:0]  raddr;      // address of the request being answered
    } mem_rsp_t;

    // ========================================================================
    // Inter-stage interfaces
    //
    //   fetch     --if_id-->        decode
    //   decode    --id_ex-->        execute
    //   execute   --ex_mem-->       memory
    //   execute   --redirect-->     fetch (mispredicted branch, jalr)
    //   memory    --mem_wb-->       register file (writeback), commit
    //   hazard    --fwd_operands--> execute (forwarded rs1/rs2)
    //
    // Control: one global stall (`mem_stall`, memory stage waiting on the
    // cache or the M unit) freezes fetch/decode/execute/memory in place; a
    // load-use (or M-use) hazard holds IF/ID for one cycle; a redirect from
    // execute flushes IF/ID and the fetch in flight.
    // ========================================================================

    // fetch -> decode
    typedef struct packed {
        logic           valid;
        logic   [31:0]  inst;
        logic   [31:0]  pc;
    } if_id_stage_reg_t;

    // decode -> execute (ID/EX pipeline register)
    typedef struct packed {
        logic           valid;
        logic   [31:0]  inst;       // for RVFI
        logic   [31:0]  pc;         // the branch's not-taken PC is pc + 4
        logic   [6:0]   opcode;
        logic   [2:0]   funct3;
        logic   [6:0]   funct7;
        logic   [4:0]   rd_s;       // 0 when the instruction writes no register
        logic   [4:0]   rs1_s;
        logic   [4:0]   rs2_s;      // 0 unless the instruction reads rs2
        logic   [31:0]  rs1_v;      // register-file values (refreshed while stalled)
        logic   [31:0]  rs2_v;
        logic   [31:0]  imm;
    } id_ex_stage_reg_t;

    // hazard unit -> execute: operands after forwarding
    typedef struct packed {
        logic   [31:0]  rs1_v;
        logic   [31:0]  rs2_v;
    } fwd_operands_t;

    // execute -> fetch: control-flow redirect
    typedef struct packed {
        logic           valid;
        logic   [31:0]  target;
    } redirect_t;

    // commit record (RVFI), same fields as the out-of-order core's rvfi_entry
    typedef struct packed {
        logic           valid;
        logic   [63:0]  order;
        logic   [31:0]  inst;
        logic   [4:0]   rs1_addr;
        logic   [4:0]   rs2_addr;
        logic   [31:0]  rs1_rdata;
        logic   [31:0]  rs2_rdata;
        logic   [4:0]   rd_addr;
        logic   [31:0]  rd_wdata;
        logic   [31:0]  pc_rdata;
        logic   [31:0]  pc_wdata;
        logic   [31:0]  mem_addr;
        logic   [3:0]   mem_rmask;
        logic   [3:0]   mem_wmask;
        logic   [31:0]  mem_rdata;
        logic   [31:0]  mem_wdata;
    } rvfi_entry;

    // execute -> memory (EX/MEM pipeline register)
    typedef struct packed {
        logic           valid;
        logic           is_load;
        logic           is_store;
        logic           is_m;       // RV32M op, result comes from m_unit
        logic   [2:0]   funct3;
        logic   [1:0]   addr_lo;    // byte offset of a load
        mem_req_t       req;        // data-cache request (held until resp)
        logic   [4:0]   rd_s;
        logic   [31:0]  rd_v;       // ALU result (not valid for loads / M ops)
        rvfi_entry      rvfi;
    } ex_mem_stage_reg_t;

    // memory -> writeback (MEM/WB pipeline register); also the commit point
    typedef struct packed {
        logic           valid;
        logic   [4:0]   rd_s;
        logic   [31:0]  rd_v;
        rvfi_entry      rvfi;
    } mem_wb_stage_reg_t;

endpackage
