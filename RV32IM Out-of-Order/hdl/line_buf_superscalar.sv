module line_buf_superscalar
import rv32i_types::*;
(
    input   logic   clk,
    input   logic   rst,
    input   logic   [31:0] pc,
    input   logic   [31:0] pc_next,
    input   logic   [255:0] ufp_rdata,
    input   logic   ufp_resp,
    output  logic   [31:0] inst_1, inst_2,
    output  logic   i_request,      //making instruction memory request
    output  logic   i_need_resp,     //for stalling logic,


    output  logic   end_linebuf,
    output  logic   inst_valid
);
    logic [255:0]   line_buf_data;
    logic [31:5]    line_buf_tag_set;
    logic           line_buf_valid;
    logic [63:0]    inst_pack;

    always_ff @(posedge clk) begin
        if (rst) begin
            line_buf_data <= '0;
            line_buf_tag_set <= '0;
            line_buf_valid <= '0;
            i_need_resp <= '0;
        end else begin
            // when need to make request, update tag_set to new cacheline
            if (i_request) begin
                line_buf_tag_set <= pc_next[31:5];
            end
            // else begin
            //     line_buf_tag_set <= line_buf_tag_set;
            // end
            // when receive new cacheline after request, store in line buffer

            if (i_need_resp && ufp_resp) begin
                line_buf_data <= ufp_rdata;

            end 
            // else begin
            //     line_buf_data <= line_buf_data;
            // end
            // need_resp handling
            if (!i_need_resp && i_request) begin
                i_need_resp <= '1;  //when make request, set need_resp
            end else if (i_need_resp && !i_request && ufp_resp) begin
                i_need_resp <= '0;  //when received and we do not request more, unset need_resp
            end 
            // else begin
            //     i_need_resp <= i_need_resp;
            // end
        end
    end

    always_comb begin
        //maybe make this i_request = pc_next[31:5] != line_buf_tag_set;
        // if (pc_next[31:5] == line_buf_tag_set) begin
        //     i_request = '0;   //next instruction in line buffer, no need to request
        // end else begin
        //     i_request = '1;   //need to request a new cacheline for next instruction
        // end

        i_request = pc_next[31:5] != line_buf_tag_set;

        inst_1 = line_buf_data[{pc[4:0], 3'd0} +: 32];
        inst_2 = line_buf_data[{(pc[4:0]+3'd4), 3'd0} +: 32];

        end_linebuf =  (pc[4:2] == 3'b111);


        inst_valid = (pc[31:5] == line_buf_tag_set && !i_need_resp) ;
        
        // if (pc[31:5] == line_buf_tag_set && !i_need_resp) begin
        //     if (pc[4:2] == 3'b111) begin
        //         end_linebuf = '1;
        //     end else begin
        //         end_linebuf = '0;
        //     end 
        // end else begin
        //     end_linebuf = '0;
        // end

        end

        // assign inst_1 = inst_pack[31:0];
        // assign inst_2 = inst_pack[63:32];
    
endmodule : line_buf_superscalar


// module line_buf_superscalar
// import rv32i_types::*;
// (
//     input   logic   clk,
//     input   logic   rst,
//     input   logic   [31:0] pc,
//     input   logic   [31:0] pc_next,
//     input   logic   [255:0] ufp_rdata,
//     input   logic   ufp_resp,
//     output  logic   [31:0] inst_1, inst_2,
//     output  logic   inst_valid,
//     output  logic   i_request,      //making instruction memory request
//     output  logic   i_need_resp,     //for stalling logic,

//     output  logic   end_linebuf
// );
//     logic [255:0]   line_buf_data;
//     logic [31:5]    line_buf_tag_set;
//     logic           line_buf_valid;
//     logic [63:0]    inst_pack;

//     always_ff @(posedge clk) begin
//         if (rst) begin
//             line_buf_data <= '0;
//             line_buf_tag_set <= '0;
//             line_buf_valid <= '0;
//             i_need_resp <= '0;
//         end else begin
//             // when need to make request, update tag_set to new cacheline
//             if (i_request) begin
//                 line_buf_tag_set <= pc_next[31:5];
//             end
//             // else begin
//             //     line_buf_tag_set <= line_buf_tag_set;
//             // end
//             // when receive new cacheline after request, store in line buffer

//             if (i_need_resp && ufp_resp) begin
//                 line_buf_data <= ufp_rdata;

//             end 
//             // else begin
//             //     line_buf_data <= line_buf_data;
//             // end
//             // need_resp handling
//             if (!i_need_resp && i_request) begin
//                 i_need_resp <= '1;  //when make request, set need_resp
//             end else if (i_need_resp && !i_request && ufp_resp) begin
//                 i_need_resp <= '0;  //when received and we do not request more, unset need_resp
//             end 
//             // else begin
//             //     i_need_resp <= i_need_resp;
//             // end
//         end
//     end

//     always_comb begin
//         //maybe make this i_request = pc_next[31:5] != line_buf_tag_set;
//         // if (pc_next[31:5] == line_buf_tag_set) begin
//         //     i_request = '0;   //next instruction in line buffer, no need to request
//         // end else begin
//         //     i_request = '1;   //need to request a new cacheline for next instruction
//         // end

//         i_request = pc_next[31:5] != line_buf_tag_set;
        
//         if (pc[31:5] == line_buf_tag_set && !i_need_resp) begin
//             inst_valid = '1;
//             if (pc[4:2] == 3'b111) begin
//                 inst_pack = {32'd0, line_buf_data[pc[4:0] * 8 +: 32]};    //read instruction from line buffer
//                 end_linebuf = '1;
//             end else begin
//                 inst_pack = line_buf_data[pc[4:0] * 8 +: 64];
//                 end_linebuf = '0;
//             end 
//         end else begin
//             inst_pack = '0;   //read inistruction from memory input
//             end_linebuf = '0;
//             inst_valid = '0;
//         end

//     end

//     assign inst_1 = inst_pack[31:0];
//     assign inst_2 = inst_pack[63:32];
    
// endmodule : line_buf_superscalar

