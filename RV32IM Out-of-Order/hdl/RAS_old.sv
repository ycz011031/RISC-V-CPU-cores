module RAS_old 
import rv32i_types::*;
#(
    parameter               RAS_HEIGHT     = 16,
    parameter               RAS_ADDR_L = 4
)(
    input   logic                   clk,
    input   logic                   rst,
    input   logic                   flush,
    input   logic                   push,
    input   logic                   pop,
    input   ras_entry_t             din,
    // input   CDB_t                   cdb,

    output  ras_entry_t             dout,
    output  logic                   full,
    output  logic                   empty,

    output logic [RAS_ADDR_L-1:0]  ras_addr
);

    logic   [RAS_ADDR_L-1:0]         top_pointer;      //next free entry
    ras_entry_t        internal_array  [RAS_HEIGHT];

    logic dummy_flush;

    assign dummy_flush = flush;


    always_ff @( posedge clk ) begin : lifo_update

        if (rst) begin
            top_pointer <= '0;
            for (integer i = 0; i < RAS_HEIGHT; i++) begin           //for loop maybe unnecessary because pointers are equal at reset
                internal_array[i] <= '0;
            end
        end else begin
            case ({push, pop})
                2'b11: begin  // simult enq and deq             //can edit this to move enq logic inside if(!empty) so that nothing happens if both asserted when empty
                    internal_array[top_pointer[RAS_ADDR_L-1:0]] <= din;
                    // if (!empty) begin
                    //     top_pointer <= top_pointer + 1'b1;
                    // end
                end
                2'b10: begin  //only enq
                    // if (!full) begin
                        internal_array[top_pointer[RAS_ADDR_L-1:0]] <= din;
                        top_pointer <= top_pointer + 1'b1; 
                    // end
                end
                2'b01: begin  // only deq
                    if (!empty)
                        top_pointer <= top_pointer - 1'b1;
                end
                default: ;
            endcase

            // if (cdb.valid && !empty && cdb.br_mispred && !cdb.br_only_taken) begin  //don't replace with pc+4 on b_type if mispredict and br_actual is taken
            //     // internal_array[cdb.ftq_addr].br_mispred <= cdb.br_mispred;
            //     internal_array[cdb.ftq_addr].br_target <= cdb.br_target;
            //     // internal_array[cdb.rob_addr].br_addr_mispred <= cdb.br_addr_mispred;
            // end
        end

    end
    assign ras_addr = top_pointer[RAS_ADDR_L-1:0];

    always_comb begin
        
        full = '0; // top_pointer[RAS_ADDR_L]; // overflow is 1 so next free entry is above stack
        empty = top_pointer == '0;
        // if (empty)
        //     dout = din;
        // else
        dout = internal_array[top_pointer[RAS_ADDR_L-1:0]];
    end

endmodule : RAS_old