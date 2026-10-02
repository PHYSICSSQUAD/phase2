//----------------------------------------------------------------------
// File       : mul_int_test_pkg.sv
// Description: PRIVATE integration tests for the MUL environment.
//              NOT part of the team environment - only used to prove
//              that mul_env works with the real CV32E40P RTL.
//
// Contents:
//   mul_int_program        : tiny hand-written programs + the expected
//                            result of every multiply, computed by hand
//   mul_int_expect_checker : compares each observed multiply with the
//                            hand-computed value (cross-checks that the
//                            monitor sees the right instructions in the
//                            right order, independent of mul_ref_model)
//   mul_int_base_test      : creates mul_env + checker, waits for the
//                            program to finish
//   mul_basic_test         : 1 MUL + 1 MULH (the "first simple test")
//   mul_all_ops_test       : all 4 ops, corner values, back-to-back and
//                            dependent multiplies
//
// No sequences: the core fetches the program from the memory in
// mul_int_tb_top, exactly like real software.
//----------------------------------------------------------------------

package mul_int_test_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import tb_pkg::*;
    import mul_pkg::*;

    // =================================================================
    // Program builder
    // =================================================================
    class mul_int_program;

        logic [31:0] code[$];        // machine code, loaded at address 0
        instr_e      exp_op[$];      // expected multiply sequence
        logic [31:0] exp_result[$];  // hand-computed expected rd values
        string       name;

        // R-type multiply. 'exp' is computed BY HAND in the comments.
        function void mul_op(instr_e op, int rd, int rs1, int rs2, logic [31:0] exp);
            code.push_back({get_funct7(op), 5'(rs2), 5'(rs1), get_funct3(op), 5'(rd), get_opcode(op)});
            exp_op.push_back(op);
            exp_result.push_back(exp);
        endfunction

        function void addi(int rd, int rs1, int imm);
            code.push_back({12'(imm), 5'(rs1), get_funct3(ADDI), 5'(rd), get_opcode(ADDI)});
        endfunction

        function void lui(int rd, logic [19:0] imm20);
            code.push_back({imm20, 5'(rd), get_opcode(LUI)});
        endfunction

        // Builds the program that belongs to a test name.
        static function mul_int_program get(string test_name);
            mul_int_program p = new();
            p.name = test_name;
            case (test_name)
                "mul_basic_test": begin
                    p.addi(1, 0, 3);                              // x1 = 3
                    p.addi(2, 0, -2);                             // x2 = 0xFFFFFFFE (-2)
                    p.mul_op(MUL,  5, 1, 2, 32'hFFFF_FFFA);      // 3 * -2 = -6
                    p.lui (3, 20'h80000);                         // x3 = 0x80000000 (-2^31)
                    p.mul_op(MULH, 6, 3, 3, 32'h4000_0000);      // 2^62 -> high = 0x40000000
                end
                "mul_all_ops_test": begin
                    p.addi(1, 0, 3);                              // x1  = 3
                    p.addi(2, 0, -2);                             // x2  = 0xFFFFFFFE
                    p.lui (3, 20'h80000);                         // x3  = 0x80000000 (min neg)
                    p.lui (4, 20'h80000);
                    p.addi(4, 4, -1);                             // x4  = 0x7FFFFFFF (max pos)
                    p.addi(15, 0, -1);                            // x15 = 0xFFFFFFFF
                    // one of each op
                    p.mul_op(MUL,     5,  1,  2, 32'hFFFF_FFFA);  // 3 * -2 = -6
                    p.mul_op(MULH,    6,  3,  3, 32'h4000_0000);  // (-2^31)^2 = 2^62
                    p.mul_op(MULHSU,  7,  2,  2, 32'hFFFF_FFFE);  // -2 * 0xFFFFFFFE = 0xFFFFFFFE_00000004
                    p.mul_op(MULHU,   8,  2,  2, 32'hFFFF_FFFC);  // 0xFFFFFFFE^2 = 0xFFFFFFFC_00000004
                    // corner values
                    p.mul_op(MULH,    9,  4,  3, 32'hC000_0000);  // max_pos*min_neg = 0xC0000000_80000000
                    p.mul_op(MULHU,  10, 15, 15, 32'hFFFF_FFFE);  // (2^32-1)^2 = 0xFFFFFFFE_00000001
                    p.mul_op(MULHSU, 11, 15, 15, 32'hFFFF_FFFF);  // -1 * (2^32-1) = 0xFFFFFFFF_00000001
                    p.mul_op(MUL,    12, 15, 15, 32'h0000_0001);  // -1 * -1 = 1
                    p.mul_op(MUL,    13,  0,  2, 32'h0000_0000);  // x0 * -2 = 0
                    // back-to-back, each one uses the previous result
                    // (checks the monitor across MULH->MUL hand-over and
                    //  operand forwarding from the EX write-back port)
                    p.mul_op(MULH,   14,  3,  4, 32'hC000_0000);  // min_neg*max_pos
                    p.mul_op(MUL,    16, 14,  1, 32'h4000_0000);  // 0xC0000000*3 = 0x2_40000000
                    p.mul_op(MULHU,  17, 16, 16, 32'h1000_0000);  // (2^30)^2 = 2^60
                    p.mul_op(MUL,    18, 17, 17, 32'h0000_0000);  // (2^28)^2 = 2^56 -> low = 0
                end
                default: `uvm_fatal("MUL_INT_PROG", {"No program for test ", test_name})
            endcase
            // Remaining memory is filled with "jal x0, 0" by tb_top, so the
            // core parks in a self-loop after the last instruction.
            return p;
        endfunction

    endclass

    // =================================================================
    // Hand-computed expectation checker (private TB only)
    // =================================================================
    class mul_int_expect_checker extends uvm_subscriber #(mul_seq_item);
        `uvm_component_utils(mul_int_expect_checker)

        mul_int_program prog;
        int unsigned    num_seen;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void write(mul_seq_item t);
            if (num_seen >= prog.exp_op.size()) begin
                `uvm_error("MUL_INT_CHK", {"Unexpected extra multiply: ", t.convert2string()})
            end
            else if (t.op !== prog.exp_op[num_seen] || t.result !== prog.exp_result[num_seen]) begin
                `uvm_error("MUL_INT_CHK", $sformatf("#%0d expected %s result=0x%08h, observed %s",
                    num_seen, prog.exp_op[num_seen].name(), prog.exp_result[num_seen], t.convert2string()))
            end
            else begin
                `uvm_info("MUL_INT_CHK", $sformatf("#%0d matches hand-computed value: %s",
                    num_seen, t.convert2string()), UVM_LOW)
            end
            num_seen++;
        endfunction

        function void check_phase(uvm_phase phase);
            if (num_seen != prog.exp_op.size())
                `uvm_error("MUL_INT_CHK", $sformatf("Observed %0d multiplies, program contains %0d",
                    num_seen, prog.exp_op.size()))
        endfunction
    endclass

    // =================================================================
    // Base test
    // =================================================================
    class mul_int_base_test extends uvm_test;
        `uvm_component_utils(mul_int_base_test)

        mul_env                env;
        mul_int_expect_checker chk;
        mul_int_program        prog;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        // build_phase: the env finds the interface handle that the bound
        // alu_mul_if registered itself - the test does not touch it.
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            prog     = mul_int_program::get(get_type_name());
            env      = mul_env::type_id::create("env", this);
            chk      = mul_int_expect_checker::type_id::create("chk", this);
            chk.prog = prog;
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            env.agent.ap.connect(chk.analysis_export);
        endfunction

        // run_phase: keep the test alive until every multiply of the
        // program was observed (or a timeout hits).
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            fork
                wait (chk.num_seen == prog.exp_op.size());
                begin
                    #100us;
                    `uvm_error(get_type_name(), "Timeout waiting for the program's multiplies")
                end
            join_any
            disable fork;
            #200ns;   // let a possible extra (wrong) multiply show up
            phase.drop_objection(this);
        endtask

        function void report_phase(uvm_phase phase);
            uvm_report_server rs = uvm_report_server::get_server();
            if (rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL) == 0)
                `uvm_info(get_type_name(), "*** TEST PASSED ***", UVM_NONE)
            else
                `uvm_info(get_type_name(), "*** TEST FAILED ***", UVM_NONE)
        endfunction
    endclass

    class mul_basic_test extends mul_int_base_test;
        `uvm_component_utils(mul_basic_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
    endclass

    class mul_all_ops_test extends mul_int_base_test;
        `uvm_component_utils(mul_all_ops_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
    endclass

endpackage
