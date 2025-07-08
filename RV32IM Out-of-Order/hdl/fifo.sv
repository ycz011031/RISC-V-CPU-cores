module fifo #(
            parameter               DEPTH     = 8,
            parameter               WIDTH     = 8
)(
    input   logic                   clk,
    input   logic                   rst,
    input   logic                   enq,
    input   logic                   deq,
    input   logic   [WIDTH-1:0]     din,

    output  logic   [WIDTH-1:0]     dout,
    output  logic                   full,
    output  logic                   empty
);

    localparam                  Q_INDEX = $clog2(DEPTH);

    logic   [Q_INDEX:0]         head, tail;      
    logic   [WIDTH-1:0]         internal_array  [DEPTH];



    always_ff @( posedge clk ) begin : fifo_update
        // if (rst) begin
        //     head <= '0;
        //     tail <= '0;
        //     for (integer i = 0; i < DEPTH; i++) begin           //for loop maybe unnecessary because pointers are equal at reset
        //         internal_array[i] <= '0;
        //     end
        // end else if (enq && deq && !empty) begin                //can edit this to move if(!empty) inside so that only enq happens if both asserted when empty
        //     internal_array[tail[Q_INDEX-1:0]] <= din;
        //     tail <= tail + {{($bits(tail)-1){1'b0}}, 1'b1}; //'d1;
        //     head <= head + {{($bits(head)-1){1'b0}}, 1'b1}; //'d1;
        // end else begin
        //     if (!full && enq) begin
        //         internal_array[tail[Q_INDEX-1:0]] <= din;
        //         tail <= tail + {{($bits(tail)-1){1'b0}}, 1'b1}; //'d1;
        //     end
        //     if (!empty && deq) begin
        //         head <= head + {{($bits(head)-1){1'b0}}, 1'b1}; //'d1;
        //     end test
        // end

        if (rst) begin
            head <= '0;
            tail <= '0;
            for (integer i = 0; i < DEPTH; i++) begin           //for loop maybe unnecessary because pointers are equal at reset
                internal_array[i] <= '0;
            end
        end else begin
            case ({enq, deq})
                2'b11: begin  // simult enq and deq             //can edit this to move enq logic inside if(!empty) so that nothing happens if both asserted when empty
                    internal_array[tail[Q_INDEX-1:0]] <= din;
                    tail <= tail + 1;
                    if (!empty) begin
                        head <= head + 1;
                    end
                end
                2'b10: begin  //only enq
                    if (!full) begin
                        internal_array[tail[Q_INDEX-1:0]] <= din;
                        tail <= tail + 1; 
                    end
                end
                2'b01: begin  // only deq
                    if (!empty)
                        head <= head + 1;
                end
                default: ;
            endcase
        end

    end


    always_comb begin
        dout = internal_array[head[Q_INDEX-1:0]];
        
        full = (head[Q_INDEX] != tail[Q_INDEX]) && (head[Q_INDEX-1:0] == tail[Q_INDEX-1:0]);
        empty = head == tail;
    end

endmodule : fifo