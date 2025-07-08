module ret_RAS 
import rv32i_types::*;
#(
    parameter               RAS_HEIGHT     = 16,
    parameter               RAS_ADDR_L = 4
)(
    input   logic                   clk,
    input   logic                   rst,
    input   logic                   push,
    input   logic                   pop,
    input   ras_entry_t             din,

    output  ras_entry_t             dout,
    output  logic                   full,
    output  logic                   empty,

    output logic [RAS_ADDR_L-1:0]  ras_flush_top
);

    logic   [RAS_ADDR_L-1:0]         top_pointer;      //next free entry
    ras_entry_t        internal_array  [RAS_HEIGHT];

    logic empty_reg;

    assign ras_flush_top = top_pointer;


    always_ff @( posedge clk ) begin : lifo_update

        if (rst) begin
            top_pointer <= '0;
            empty_reg <= '1;
            for (integer i = 0; i < RAS_HEIGHT; i++) begin           //for loop maybe unnecessary because pointers are equal at reset
                internal_array[i] <= '0;
            end
        end else begin
            case ({push, pop})
                2'b11: begin  // simult enq and deq             //can edit this to move enq logic inside if(!empty) so that nothing happens if both asserted when empty
                    internal_array[top_pointer] <= din;
                    if (empty_reg) begin
                        empty_reg <= '0;
                    end
                end
                2'b10: begin  //only enq
                    if (!full) begin
                        if (empty_reg) begin
                            internal_array[top_pointer] <= din;
                            empty_reg <= '0;
                        end else begin
                            top_pointer <= top_pointer + 1'b1;
                            internal_array[top_pointer + 1'b1] <= din;
                        end 
                    end
                end
                2'b01: begin  // only deq
                    if (!empty_reg) begin
                        if(top_pointer == '0) begin
                            empty_reg <= '1;
                        end else begin
                            top_pointer <= top_pointer - 1'b1;
                        end
                    end
                end
                default: ;
            endcase
        end

    end

    always_comb begin
        
        full = top_pointer == '1; // overflow is 1 so next free entry is above stack
        empty = empty_reg;
        dout = empty_reg ? '0 : internal_array[top_pointer];
    end

endmodule : ret_RAS