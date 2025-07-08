module free_list #(
    parameter               PADDR_L     = 8
)(
    input   logic                   clk,
    input   logic                   rst,
    input   logic                   flush,

    input   logic                   enq1,
    input   logic                   enq2,

    input   logic                   deq1,
    input   logic                   deq2,

    output  logic   [PADDR_L-1:0]   next_addr1,
    output  logic   [PADDR_L-1:0]   next_addr2,

    output  logic                   full,
    output  logic                   almost_full,
    output  logic                   empty,
    output  logic                   almost_empty,
    
    output  logic                   error
);

    localparam                  PRF_SIZE = 2 ** PADDR_L;

    logic   [PADDR_L:0]         head, tail;
    logic   [PADDR_L:0]         head_next, tail_next;

    assign head_next = head + 1'b1;
    assign tail_next = tail + 1'b1;

    always_ff @( posedge clk ) begin
        if (rst||flush) begin
            head <= '0;
            tail <= PRF_SIZE[PADDR_L:0];
            error <= '0;
        end else begin
            error <= '0;
            case ({enq1, enq2, deq1, deq2})  
                4'b1000, 4'b0100: begin  //one enq
                    if (!full) begin
                        tail <= tail + 1'b1; 
                    end else begin
                        error <= '1;
                    end
                end
                4'b0010, 4'b0001: begin  //one deq
                    if (!empty) begin
                        head <= head + 1'b1;
                    end else begin
                        error <= '1;
                    end
                end
                4'b1100: begin  // two enq
                    if (!full) begin
                        if (!almost_full) begin
                            tail <= tail + 2'd2; 
                        end else begin
                            error <= '1;
                        end
                    end else begin
                        error <= '1;
                    end
                end
                4'b1010, 4'b1001, 4'b0110, 4'b0101: begin  //one enq and one deq
                    tail <= tail + 1'b1;
                    if (!empty) begin
                        head <= head + 1'b1;
                    end else begin
                        error <= '1;
                    end
                end
                4'b0011: begin  // two deq
                    if (!empty) begin
                        if (!almost_empty) begin
                            head <= head + 2'd2;
                        end else begin
                            error <= '1;
                        end
                    end else begin
                        error <= '1;
                    end
                end
                4'b1011, 4'b0111: begin  // one enq and two deq
                    tail <= tail + 1'b1;
                    if (!empty) begin
                        if (!almost_empty) begin
                            head <= head + 2'd2;
                        end else begin
                            error <= '1;
                        end
                    end else begin
                        error <= '1;
                    end
                end
                4'b1110, 4'b1101: begin  // two enq and one deq
                    if (!empty) begin
                        head <= head + 1'b1;
                    end else begin
                        error <= '1;
                    end
                    if (!full) begin
                        tail <= tail + 2'd2; 
                    end else begin
                        error <= '1;
                    end
                end
                4'b1111: begin  // two enq and two deq
                    if (!empty) begin
                        if (!almost_empty) begin
                            head <= head + 2'd2;
                        end else begin
                            error <= '1;
                        end
                    end else begin
                        error <= '1;
                    end
                    tail <= tail + 2'd2; 
                end
                default: ;
            endcase
        end
    end


    always_comb begin
        case ({deq1, deq2})
            2'b11: begin  // simult enq and deq
                next_addr1 = (empty) ? '0 : head[PADDR_L-1:0];
                next_addr2 = (empty || almost_empty) ? '0 : head_next[PADDR_L-1:0];
            end
            2'b10: begin  //only enq
                next_addr2 = '0;
                next_addr1 = (empty) ? '0 : head[PADDR_L-1:0];
            end
            2'b01: begin  // only deq
                next_addr1 = '0;
                next_addr2 = (empty) ? '0 : head[PADDR_L-1:0];
            end
            default: begin
                next_addr1 = '0;
                next_addr2 = '0;
            end
        endcase
        full = (head[PADDR_L] != tail[PADDR_L]) && (head[PADDR_L-1:0] == tail[PADDR_L-1:0]);
        almost_full = (head[PADDR_L] != tail_next[PADDR_L]) && (head[PADDR_L-1:0] == tail_next[PADDR_L-1:0]) || full;

        empty = head == tail;
        almost_empty = head_next == tail || empty;
    end

endmodule : free_list