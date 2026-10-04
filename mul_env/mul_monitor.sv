//----------------------------------------------------------------------
// File       : mul_monitor.sv
// Description: Passive monitor of the RV32M MUL/DIV agent. Watches the
//              ALU_MUL interface and publishes ONE mul_seq_item for
//              every MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU that
//              completes in EX.
//
// Why a monitor (and no driver)?
// - The core fetches its own instructions (driven by the Instruction
//   agent). The MUL agent must never drive anything; it only observes.
//
// Pipeline facts this monitor relies on (RTL + databook):
// - ID -> EX: the ID/EX registers (incl. mult_en_ex and the operands)
//   are loaded ONLY on a clock edge where id_valid=1, with the
//   instruction that is in ID (cv32e40p_id_stage). So the instruction
//   in EX is always the one that was in ID at the last id_valid edge.
// - MUL takes 1 cycle in EX, MULH/MULHSU/MULHU take 5 cycles
//   (cv32e40p_mult MUL_H FSM: IDLE->STEP0->STEP1->STEP2->FINISH).
// - DIV/DIVU/REM/REMU run in cv32e40p_alu_div and take 3..35 cycles.
//   They use the ALU path (ex_alu_en), not the multiplier path.
// - ex_valid=1 only in the cycle the EX instruction finishes. During
//   any multi-cycle iterations ex_valid=0, so intermediate values are
//   never checked.
// - Instructions in EX are never flushed (branches resolve in EX and
//   only flush IF/ID), so every operation that enters EX completes.
//
// Algorithm, at every rising clock edge (sampled through mon_cb):
//   (1) COMPLETE: if ex_valid and either the multiplier is enabled or
//       the recorded instruction is DIV/REM on the ALU path, EX finishes
//       now -> build item from the recorded word + operands + write-back
//       data -> ap.write().
//   (2) ENTER   : if id_valid, the instruction in ID moves into EX now
//       -> remember its word. We record EVERY instruction. Normal ALU
//       instructions are ignored because they are not DIV/REM encodings.
//   Order matters: a new MUL may enter EX on the same edge the old one
//   leaves, so first finish the old one, then record the new one.
//
// Transaction flow:
//   DUT signals --> alu_mul_if.mon_cb --> mul_monitor --ap--> scoreboard
//                                                        \--> coverage
//----------------------------------------------------------------------

class mul_monitor extends uvm_monitor;

    `uvm_component_utils(mul_monitor)

    // Analysis port: a "broadcast" output. write(item) calls write() of
    // every connected subscriber (scoreboard, coverage) immediately.
    // The monitor does not need to know who is listening.
    uvm_analysis_port #(mul_seq_item) ap;

    mul_config         cfg;
    virtual alu_mul_if vif;

    // State between step (2) and step (1): the instruction now in EX.
    logic [31:0] ex_instr;         // instruction word that entered EX
    bit          ex_instr_valid;   // 1 = ex_instr belongs to the instruction now in EX

    // Simple statistic printed in report_phase.
    int unsigned num_items;

    function new(string name = "mul_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // build_phase: create ports and fetch the configuration.
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(mul_config)::get(this, "", "mul_cfg", cfg)) begin
            `uvm_fatal(get_type_name(), "mul_config 'mul_cfg' not found in uvm_config_db")
        end
        vif = cfg.vif;
        if (vif == null) begin
            `uvm_fatal(get_type_name(), "mul_config.vif is null - is alu_mul_bind.sv compiled and alu_mul_bind instantiated in tb_top?")
        end
    endfunction

    // run_phase: endless sampling loop (a monitor never ends the test).
    task run_phase(uvm_phase phase);
        ex_instr_valid = 0;
        num_items      = 0;
        forever begin
            @(vif.mon_cb);

            // Reset clears the pipeline, so anything we were tracking is
            // gone. Forget it and wait for the next valid instruction.
            if (vif.mon_cb.rst_n !== 1'b1) begin
                ex_instr_valid = 0;
                continue;
            end

            // ---- (1) COMPLETE: current EX instruction leaves now ----
            if (vif.mon_cb.ex_valid === 1'b1) begin
                // All MUL operations use ex_mult_en. DIV/REM use the ALU,
                // so identify those from the independently decoded word.
                if (vif.mon_cb.ex_mult_en === 1'b1 ||
                    (vif.mon_cb.ex_alu_en === 1'b1 && ex_instr_valid && is_div_or_rem(ex_instr))) begin
                    if (!ex_instr_valid) begin
                        `uvm_error(get_type_name(),
                            "RV32M operation completed but no instruction was seen entering EX")
                    end
                    else begin
                        publish_item();
                    end
                end
                // The current EX instruction is gone, even when it was a
                // normal non-RV32M ALU instruction that we did not publish.
                ex_instr_valid = 0;
            end

            // ---- (2) ENTER: ID instruction moves into EX on this edge ----
            if (vif.mon_cb.id_valid === 1'b1) begin
                ex_instr       = vif.mon_cb.id_instr;
                ex_instr_valid = 1;
            end
        end
    endtask

    // Build one transaction from the current mon_cb sample and send it.
    function void publish_item();
        mul_seq_item item;
        instr_e      op;

        // Decode the recorded instruction. Anything using the multiplier
        // that is not one of the 8 standard RV32M operations (for example
        // a PULP dot-product) is reported, never silently dropped.
        if (!decode_m_op(ex_instr, op)) begin
            `uvm_error(get_type_name(),
                $sformatf("Execution unit used by a non-supported RV32M instruction 0x%08h - not checked", ex_instr))
            return;
        end

        // "create" (factory) instead of "new" so a test could override
        // the item type without changing this code.
        item          = mul_seq_item::type_id::create("item");
        item.instr    = ex_instr;
        item.op       = op;
        item.rd       = item.instr.r_type.rd;
        if (is_div_op(op)) begin
            // cv32e40p_decoder deliberately swaps the ALU inputs for
            // DIV/REM: EX A is architectural rs2 and EX B is rs1.
            item.rs1_val = vif.mon_cb.ex_alu_operand_b;
            item.rs2_val = vif.mon_cb.ex_alu_operand_a;
        end
        else begin
            item.rs1_val = vif.mon_cb.ex_mult_operand_a;
            item.rs2_val = vif.mon_cb.ex_mult_operand_b;
        end
        item.result   = vif.mon_cb.ex_wb_wdata;
        item.wb_we    = vif.mon_cb.ex_wb_we;
        item.wb_waddr = vif.mon_cb.ex_wb_waddr;

        num_items++;
        `uvm_info(get_type_name(), {"Observed: ", item.convert2string()}, UVM_HIGH)
        ap.write(item);
    endfunction

    // Returns 1 for one of the 8 standard RV32M operations. Uses the
    // shared tb_pkg helpers, independently of the DUT decoder.
    function bit decode_m_op(logic [31:0] raw, output instr_e op);
        instr_t i;
        instr_e cand[8] = '{MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU};
        i = raw;
        foreach (cand[k]) begin
            if (i.r_type.opcode === get_opcode(cand[k]) &&
                i.r_type.funct3 === get_funct3(cand[k]) &&
                i.r_type.funct7 === get_funct7(cand[k])) begin
                op = cand[k];
                return 1;
            end
        end
        op = MUL;
        return 0;
    endfunction

    function bit is_div_op(instr_e op);
        return op == DIV || op == DIVU || op == REM || op == REMU;
    endfunction

    function bit is_div_or_rem(logic [31:0] raw);
        instr_e op;
        return decode_m_op(raw, op) && is_div_op(op);
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(),
            $sformatf("RV32M monitor published %0d multiply/divide transactions", num_items), UVM_LOW)
    endfunction

endclass
