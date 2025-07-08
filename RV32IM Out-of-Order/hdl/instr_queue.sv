module instr_queue 
import rv32i_types::*;
#(
            parameter               DEPTH     = 8
)(
    input   logic                   clk,
    input   logic                   rst,
    input   logic                   flush,
    input   logic                   enq,
    input   logic                   deq,
    input   if_id_stage_reg_t       din,

    output  if_id_stage_reg_t       dout,
    output  logic                   full,
    output  logic                   empty
);

    localparam                  Q_INDEX = $clog2(DEPTH);

    logic   [Q_INDEX:0]         head, tail;      
    if_id_stage_reg_t        internal_array  [DEPTH];



    always_ff @( posedge clk ) begin : fifo_update

        if (rst||flush) begin
            head <= '0;
            tail <= '0;
            for (integer i = 0; i < DEPTH; i++) begin           //for loop maybe unnecessary because pointers are equal at reset
                internal_array[i].i_valid <= '0;
            end
        end else begin
            case ({enq, deq})
                2'b11: begin  // simult enq and deq             //can edit this to move enq logic inside if(!empty) so that nothing happens if both asserted when empty
                    if (!empty) begin
                        internal_array[tail[Q_INDEX-1:0]] <= din;
                        tail <= tail + 1'b1;
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
        end

    end


    always_comb begin
        
        full = (head[Q_INDEX] != tail[Q_INDEX]) && (head[Q_INDEX-1:0] == tail[Q_INDEX-1:0]);
        empty = head == tail;
        if (empty)
            dout = din;
        else
            dout = internal_array[head[Q_INDEX-1:0]];
    end

endmodule : instr_queue