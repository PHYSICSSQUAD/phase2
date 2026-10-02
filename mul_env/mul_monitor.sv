//----------------------------------------------------------------------
// File       : mul_monitor.sv
// Description: Passive monitor of the MUL agent. Watches the ALU_MUL
//              interface and publishes ONE mul_seq_item for every
//              MUL / MULH / MULHSU / MULHU that completes in EX.
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
// - ex_valid=1 only in the cycle the EX instruction finishes. During
//   the MULH* iterations ex_valid=0, and the write-back data shows
//   intermediate values that must NOT be checked.
// - Instructions in EX are never flushed (branches resolve in EX and
//   only flush IF/ID), so every multiplier that enters EX completes.
//
// Algorithm, at every rising clock edge (sampled through mon_cb):
//   (1) COMPLETE: if ex_mult_en && ex_valid, the multiplier in EX
//       finishes now -> build item from the instruction word recorded
//       at step (2) earlier + operands + write-back data -> ap.write().
//   (2) ENTER   : if id_valid, the instruction in ID moves into EX now
//       -> remember its word. We record EVERY instruction (not only
//       multiplies): if it is not a multiply, ex_mult_en stays 0 and
//       step (1) simply never uses it. This needs no decoder signal.
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

            // ---- (1) COMPLETE: multiplier leaves EX on this edge ----
            if (vif.mon_cb.ex_mult_en === 1'b1 && vif.mon_cb.ex_valid === 1'b1) begin
                if (!ex_instr_valid) begin
                    `uvm_error(get_type_name(),
                        "EX multiplier completed but no multiplier instruction was seen entering EX")
                end
                else begin
                    publish_item();
                end
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

        // Decode the recorded instruction. Anything that is not one of
        // the 4 multiply instructions is out of MUL scope (e.g. a PULP
        // dot-product). It is reported, never silently dropped.
        if (!decode_mul(ex_instr, op)) begin
            `uvm_error(get_type_name(),
                $sformatf("Multiplier used by a non RV32M-MUL instruction 0x%08h - not checked", ex_instr))
            return;
        end

        // "create" (factory) instead of "new" so a test could override
        // the item type without changing this code.
        item          = mul_seq_item::type_id::create("item");
        item.instr    = ex_instr;
        item.op       = op;
        item.rd       = item.instr.r_type.rd;
        item.rs1_val  = vif.mon_cb.ex_mult_operand_a;
        item.rs2_val  = vif.mon_cb.ex_mult_operand_b;
        item.result   = vif.mon_cb.ex_wb_wdata;
        item.wb_we    = vif.mon_cb.ex_wb_we;
        item.wb_waddr = vif.mon_cb.ex_wb_waddr;

        num_items++;
        `uvm_info(get_type_name(), {"Observed: ", item.convert2string()}, UVM_HIGH)
        ap.write(item);
    endfunction

    // Returns 1 and the instruction name if 'raw' is MUL/MULH/MULHSU/MULHU.
    // Uses the encoding helpers of the shared tb_pkg so every team decodes
    // instructions the same way.
    function bit decode_mul(logic [31:0] raw, output instr_e op);
        instr_t      i;
        instr_e      cand[4] = '{MUL, MULH, MULHSU, MULHU};
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

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(),
            $sformatf("MUL monitor published %0d multiplier transactions", num_items), UVM_LOW)
    endfunction

endclass
