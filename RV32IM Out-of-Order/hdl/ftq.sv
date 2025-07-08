module ftq 
import rv32i_types::*;
#(
            parameter               DEPTH     = 16,
            parameter               Q_INDEX = 4
)(
    input   logic                   clk,
    input   logic                   rst,
    input   logic                   flush,
    input   logic                   enq,
    input   logic                   deq,
    input   ftq_entry_t       din,
    input   CDB_t                   cdb,

    output  ftq_entry_t       dout,
    output  logic                   full,
    output  logic                   empty,

    output logic [Q_INDEX-1:0]  ftq_addr,

    input logic  [Q_INDEX-1:0]  funcbr_ftq_addr,
    output ftq_entry_t          to_funcbr 
);

    logic   [Q_INDEX:0]         head, tail;      
    ftq_entry_t        internal_array  [DEPTH];



    always_ff @( posedge clk ) begin : fifo_update

        if (rst||flush) begin
            head <= '0;
            tail <= '0;
            for (integer i = 0; i < DEPTH; i++) begin           //for loop maybe unnecessary because pointers are equal at reset
                internal_array[i] <= '0;
            end
        end else begin
            case ({enq, deq})
                2'b11: begin  // simult enq and deq             //can edit this to move enq logic inside if(!empty) so that nothing happens if both asserted when empty
                    internal_array[tail[Q_INDEX-1:0]] <= din;
                    tail <= tail + 1'b1;
                    if (!empty) begin
                        head <= head + 1'b1;
                    end
                end
                2'b10: begin  //only enq
                    if (!full) begin
                        internal_array[tail[Q_INDEX-1:0]] <= din;
                        tail <= tail + 1'b1; 
                    end
                end
                2'b01: begin  // only deq
                    if (!empty)
                        head <= head + 1'b1;
                end
                default: ;
            endcase

            if (cdb.valid && !empty && cdb.br_mispred && !cdb.br_only_taken) begin  //don't replace with pc+4 on b_type if mispredict and br_actual is taken
                // internal_array[cdb.ftq_addr].br_mispred <= cdb.br_mispred;
                internal_array[cdb.ftq_addr].br_target <= cdb.br_target;
                // internal_array[cdb.rob_addr].br_addr_mispred <= cdb.br_addr_mispred;
            end
        end

    end

    assign ftq_addr = tail[Q_INDEX-1:0];


    always_comb begin
        
        full = (head[Q_INDEX] != tail[Q_INDEX]) && (head[Q_INDEX-1:0] == tail[Q_INDEX-1:0]);
        empty = head == tail;
        // if (empty)
        //     dout = din;
        // else
        dout = internal_array[head[Q_INDEX-1:0]];

        to_funcbr = internal_array[funcbr_ftq_addr];
    end

endmodule : ftq