//----------------------------------------------------------------------
// File       : mul_seq_item.sv
// Description: One observed RV32M multiply/divide instruction (MUL,
//              MULH, MULHSU, MULHU, DIV, DIVU, REM or REMU) as it
//              completed in the EX stage.
//
// Why "seq_item" if there is no sequence?
// - The team names every transaction class *_seq_item. Here it is only
//   used as an ANALYSIS transaction: the monitor creates it, and the
//   scoreboard and coverage receive copies of it. Nothing randomizes
//   it, so no field is "rand".
//
// Why does ONE item hold operands AND result?
// - The monitor sees both in the same clock cycle (completion cycle of
//   the instruction in EX). The EX operands stay stable while MULH* or
//   DIV/REM iterates. Packing them together means the scoreboard needs
//   no FIFOs and no matching logic: each item is self-contained.
//
// Transaction flow:
//   mul_monitor --(creates item)--> ap.write(item)
//        |--> mul_scoreboard.write(item)  : predict + compare
//        |--> mul_coverage.write(item)    : sample covergroup
//----------------------------------------------------------------------

class mul_seq_item extends uvm_sequence_item;

    `uvm_object_utils(mul_seq_item)

    // ---------------- What instruction was executed ------------------
    instr_t      instr;      // raw 32-bit encoding (tb_pkg union type)
    instr_e      op;         // decoded name: MUL / MULH / MULHSU / MULHU
    logic [4:0]  rd;         // destination register from the encoding

    // ---------------- Inputs seen by the multiplier ------------------
    logic [31:0] rs1_val;    // operand a (value of rs1)
    logic [31:0] rs2_val;    // operand b (value of rs2)

    // ---------------- Outputs produced by the DUT --------------------
    logic [31:0] result;     // value written to rd (EX write-back data)
    logic        wb_we;      // EX write-back enable at completion
    logic [5:0]  wb_waddr;   // EX write-back address at completion

    function new(string name = "mul_seq_item");
        super.new(name);
    endfunction

    // One-line text used by every `uvm_info / `uvm_error of the env.
    function string convert2string();
        return $sformatf("%-6s rd=x%0d rs1_val=0x%08h rs2_val=0x%08h result=0x%08h (instr=0x%08h we=%0b waddr=%0d)",
                         op.name(), rd, rs1_val, rs2_val, result,
                         instr.raw, wb_we, wb_waddr);
    endfunction

    // Field-by-field copy (used by clone()).
    function void do_copy(uvm_object rhs);
        mul_seq_item rhs_;
        if (!$cast(rhs_, rhs)) begin
            `uvm_fatal(get_type_name(), "do_copy: rhs is not a mul_seq_item")
        end
        super.do_copy(rhs);
        instr    = rhs_.instr;
        op       = rhs_.op;
        rd       = rhs_.rd;
        rs1_val  = rhs_.rs1_val;
        rs2_val  = rhs_.rs2_val;
        result   = rhs_.result;
        wb_we    = rhs_.wb_we;
        wb_waddr = rhs_.wb_waddr;
    endfunction

    // Field-by-field compare (used by compare()). "===" so that X/Z
    // values coming from the DUT are never treated as a match.
    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        mul_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return super.do_compare(rhs, comparer)  &&
               (instr.raw === rhs_.instr.raw)   &&
               (rs1_val   === rhs_.rs1_val)     &&
               (rs2_val   === rhs_.rs2_val)     &&
               (result    === rhs_.result)      &&
               (wb_we     === rhs_.wb_we)       &&
               (wb_waddr  === rhs_.wb_waddr);
    endfunction

endclass
