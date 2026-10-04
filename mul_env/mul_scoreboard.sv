class mul_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(mul_scoreboard)

    uvm_analysis_imp #(mul_seq_item, mul_scoreboard) analysis_export;

    mul_ref_model ref_model;

    int unsigned pass_count;
    int unsigned fail_count;

    int unsigned op_count[instr_e];

    function new(string name = "mul_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);
        ref_model       = mul_ref_model::type_id::create("ref_model");
        pass_count      = 0;
        fail_count      = 0;
    endfunction

    function void write(mul_seq_item item);
        logic [31:0] expected;
        bit          ok;

        expected = ref_model.predict(item.op, item.rs1_val, item.rs2_val);

        ok = (item.result   === expected)          &&
             (item.wb_we    === 1'b1)              &&
             (item.wb_waddr === {1'b0, item.rd});

        if (op_count.exists(item.op)) op_count[item.op]++;
        else                          op_count[item.op] = 1;

        if (ok) begin
            pass_count++;
            `uvm_info(get_type_name(),
                $sformatf("PASS     %-6s rs1=0x%08h rs2=0x%08h expected=0x%08h actual=0x%08h rd=x%0d",
                          item.op.name(), item.rs1_val, item.rs2_val, expected, item.result, item.rd),
                UVM_MEDIUM)
        end
        else begin
            fail_count++;
            `uvm_error(get_type_name(),
                $sformatf("MISMATCH %-6s instr=0x%08h rs1=0x%08h rs2=0x%08h expected=0x%08h actual=0x%08h | rd=x%0d wb_we=%0b (exp 1) wb_waddr=%0d (exp %0d)",
                          item.op.name(), item.instr.raw, item.rs1_val, item.rs2_val, expected, item.result,
                          item.rd, item.wb_we, item.wb_waddr, item.rd))
        end
    endfunction

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (pass_count + fail_count == 0) begin
            `uvm_warning(get_type_name(), "No MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU instruction was checked in this test")
        end
    endfunction

    function void report_phase(uvm_phase phase);
        string s;
        super.report_phase(phase);
        s = $sformatf("\n-------------- RV32M MUL/DIV SCOREBOARD SUMMARY ----------\n");
        s = {s, $sformatf("  Checked : %0d   PASS : %0d   FAIL : %0d\n",
                          pass_count + fail_count, pass_count, fail_count)};
        foreach (op_count[op]) begin
            s = {s, $sformatf("  %-6s : %0d\n", op.name(), op_count[op])};
        end
        s = {s, "---------------------------------------------------------"};
        `uvm_info(get_type_name(), s, UVM_NONE)
    endfunction

endclass
