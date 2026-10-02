//----------------------------------------------------------------------
// File       : alu_mul_if.sv
// Description: "ALU_MUL interface" from the team architecture diagram.
//              The passive window that the MUL agent (and later the
//              ALU agent) uses to observe the EX stage of CV32E40P.
//
// Why does it observe INTERNAL signals?
// - cv32e40p_top has no multiplier ports. The multiplier lives in the
//   EX stage and its result is written to the register file from EX
//   (databook, "Pipeline Details"). The guidelines ask for scoreboards
//   inside the datapath, so we must observe pipeline signals.
//
// How is it connected? -> by "bind", see alu_mul_bind.sv
// - All observed signals are INPUT PORTS of this interface. The bind
//   statement creates this interface INSIDE cv32e40p_core and connects
//   the ports to the core's local signals. No RTL file is modified and
//   tb_top contains no hierarchical paths into the DUT.
// - Every port is an input: the testbench only observes, it never
//   drives anything back into the core.
//
// How does the UVM side get the handle?
// - The interface lives inside the DUT, so tb_top cannot easily pass
//   it to uvm_config_db. Instead the small wrapper module in
//   alu_mul_bind.sv (which holds this interface) registers it under
//   the name "alu_mul_vif".
//
// Sharing with the ALU agent:
// - Only MUL-related signals are declared here. ex_valid and the EX
//   write-back port are common to MUL and ALU; the ALU owner adds the
//   ALU-only ports in the marked section (and in alu_mul_bind.sv).
//----------------------------------------------------------------------

`timescale 1ns/1ps

interface alu_mul_if (
    // gated core clock / active-low reset
    input logic        clk,
    input logic        rst_n,

    // ---------------- ID -> EX hand-off -----------------------------
    // The EX stage keeps only decoded control signals, not the
    // instruction word. The monitor records the word when it moves
    // from ID to EX so it can identify MUL/MULH/MULHSU/MULHU from the
    // real encoding, independently of the DUT's own decoder.
    input logic        id_valid,          // 1 = ID instruction enters EX at this edge
    input logic [31:0] id_instr,          // instruction word currently in ID

    // ---------------- EX stage multiplier ---------------------------
    input logic        ex_mult_en,        // ID/EX reg: multiplier instruction in EX
                                          // (1 cycle for MUL, 5 for MULH*)
    input logic [31:0] ex_mult_operand_a, // ID/EX reg: rs1 value (stable while MULH* iterates)
    input logic [31:0] ex_mult_operand_b, // ID/EX reg: rs2 value
    input logic        ex_valid,          // EX instruction finishes THIS cycle. The only
                                          // cycle in which a MULH* result is final.

    // ---------------- EX write-back port (ALU/MUL/DIV -> RF) --------
    // This is how a MUL result becomes architecturally visible.
    input logic        ex_wb_we,          // write enable
    input logic [5:0]  ex_wb_waddr,       // rd (bit 5 = FP regs, always 0 for RV32IM)
    input logic [31:0] ex_wb_wdata        // value written to rd (= multiplier result)

    // ---------------- ALU-only ports: reserved for the ALU owner ----
);

    // =================================================================
    // Monitor clocking block
    // =================================================================
    // "input #1step" samples every signal just BEFORE the rising edge,
    // i.e. exactly the values the DUT flops capture on that edge. This
    // removes any race between the DUT updating and the monitor reading.
    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n;
        input id_valid, id_instr;
        input ex_mult_en, ex_mult_operand_a, ex_mult_operand_b, ex_valid;
        input ex_wb_we, ex_wb_waddr, ex_wb_wdata;
    endclocking

    // Passive agents only need the monitor view: no driver modport.
    modport MON (clocking mon_cb, input clk, input rst_n);

endinterface
