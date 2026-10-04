class mul_monitor extends uvm_monitor;

    `uvm_component_utils(mul_monitor)

    uvm_analysis_port #(mul_seq_item) ap;

    mul_config         cfg;
    virtual alu_mul_if vif;

    logic [31:0] ex_instr;
    bit          ex_instr_valid;

    int unsigned num_items;

    function new(string name = "mul_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

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

    task run_phase(uvm_phase phase);
        ex_instr_valid = 0;
        num_items      = 0;
        forever begin
            @(vif.mon_cb);

            if (vif.mon_cb.rst_n !== 1'b1) begin
                ex_instr_valid = 0;
                continue;
            end

            if (vif.mon_cb.ex_valid === 1'b1) begin

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

                ex_instr_valid = 0;
            end

            if (vif.mon_cb.id_valid === 1'b1) begin
                ex_instr       = vif.mon_cb.id_instr;
                ex_instr_valid = 1;
            end
        end
    endtask

    function void publish_item();
        mul_seq_item item;
        instr_e      op;

        if (!decode_m_op(ex_instr, op)) begin
            `uvm_error(get_type_name(),
                $sformatf("Execution unit used by a non-supported RV32M instruction 0x%08h - not checked", ex_instr))
            return;
        end

        item          = mul_seq_item::type_id::create("item");
        item.instr    = ex_instr;
        item.op       = op;
        item.rd       = item.instr.r_type.rd;
        if (is_div_op(op)) begin

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
