//-----------------------------------------------------------------------------
// Title                 : random_tb
// Project               : ECE 411 mp_verif
//-----------------------------------------------------------------------------
// File                  : random_tb.sv
// Author                : ECE 411 Course Staff
//-----------------------------------------------------------------------------
// IMPORTANT: If you don't change the random seed, every time you do a `make run`
// you will run the /same/ random test. SystemVerilog calls this "random stability",
// and it's to ensure you can reproduce errors as you try to fix the DUT. Make sure
// to change the random seed or run more instructions if you want more extensive
// coverage.
//------------------------------------------------------------------------------
module random_tb
import rv32i_types::*;
(
    mem_itf_banked.mem itf
);

//TODO Need to manage ready signal

    initial begin
        itf.rvalid = 1'b0;
        itf.raddr = '0;
        itf.ready = '1;
    end

    `include "randinst.svh"

    RandInst gen = new();

    // Do a bunch of LUIs to get useful register state.
    task init_register_state();
        logic [255:0] burst_data;
        logic [31:0]  raddr;

        for (int i = 0; i < 8; ++i) begin
            @(posedge itf.clk iff itf.read);
            raddr <= itf.addr;

            repeat (2) @(posedge itf.clk);

            for (int j = 0; j< 8; j++) begin
                if (j % 2 == 0) begin
                    gen.randomize() with {
                        instr.j_type.opcode == op_b_lui;
                        instr.j_type.rd == i[5:1];
                    };
                end else begin
                    gen.randomize() with {
                        instr.i_type.opcode == op_b_imm;
                        instr.i_type.rs1 == i[5:1];
                        instr.i_type.funct3 == arith_f3_add;
                        instr.i_type.rd == i[5:1];
                    };
                end
                burst_data[j*32 +:32] = gen.instr.word;
            end
            // Your code here: package these memory interactions into a task.
            itf.rvalid <= 1'b1;
            itf.raddr <= raddr;

            for (int b = 0; b < 4; b++) begin
                itf.rdata <= burst_data[b*64 +: 64];
                @(posedge itf.clk);
            end
            itf.rvalid <= 1'b0;
            itf.raddr <= '0;

        end

    endtask : init_register_state

    // Note that this memory model is not consistent! It ignores
    // writes and always reads out a random, valid instruction.
    task run_random_instrs();
        logic [255:0] burst_data;
        logic [31:0]  raddr;
        repeat (10000) begin
            @(posedge itf.clk iff (itf.read || itf.write));

            // Always read out a valid instruction.
            if (itf.read) begin
                raddr <= itf.addr;
                repeat (2) @(posedge itf.clk);

                for (int i =0; i<8 ; i++) begin
                    gen.randomize();
                    burst_data[i*32 +:32] = gen.instr.word;
                end

                // itf.rvalid <= 1'b1;
                itf.raddr <= raddr;

                for (int b = 0; b < 4; b++) begin
                    itf.rdata <= burst_data[b*64 +: 64];
                    itf.rvalid <= 1'b1;
                    @(posedge itf.clk);
                end
            end

            // If it's a write, do nothing.
            itf.rvalid <= 1'b0;
            itf.raddr <= '0;
            

        end
    endtask : run_random_instrs

    always @(posedge itf.clk iff !itf.rst) begin
        if ($isunknown(itf.read) || $isunknown(itf.write)) begin
            $error("Memory Error: read or write contains 1'bx");
            itf.error <= 1'b1;
        end
        if ((itf.read) && (itf.write)) begin
            $error("Memory Error: Simultaneous memory read and write");
            itf.error <= 1'b1;
        end
        if ((itf.read) || (itf.write)) begin
            if ($isunknown(itf.addr[0])) begin
                $error("Memory Error: Address contained 'x");
                itf.error <= 1'b1;
            end
            // TODO: change alignment conditions - prev: Only check for 16-bit alignment since instructions are
            // allowed to be at 16-bit boundaries due to JALR.
            if (itf.addr[0] != 1'b0) begin
                $error("Memory Error: Address is not 16-bit aligned");
                itf.error <= 1'b1;
            end
        end
    end

    // A single initial block ensures random stability.
    initial begin

        // Wait for reset.
        @(posedge itf.clk iff itf.rst == 1'b0);

        // Get some useful state into the processor by loading in a bunch of state.
        init_register_state();

        // Run!
        run_random_instrs();

        // Finish up
        $display("Random testbench finished!");
        $finish;
    end

endmodule : random_tb
