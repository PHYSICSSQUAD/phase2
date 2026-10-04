`ifdef MUL_PRIVATE_TB_TYPES

package tb_pkg;

    typedef struct packed {
        logic [6:0] funct7;
        logic [4:0] rs2;
        logic [4:0] rs1;
        logic [2:0] funct3;
        logic [4:0] rd;
        logic [6:0] opcode;
    } r_type_t;

    typedef union packed {
        logic [31:0] raw;
        r_type_t     r_type;
    } instr_t;

    typedef enum logic [3:0] {
        LUI, ADDI,
        MUL, MULH, MULHSU, MULHU,
        DIV, DIVU, REM, REMU
    } instr_e;

    function bit [6:0] get_opcode(instr_e op);
        case (op)
            LUI:     return 7'b0110111;
            ADDI:    return 7'b0010011;
            default: return 7'b0110011;
        endcase
    endfunction

    function bit [2:0] get_funct3(instr_e op);
        case (op)
            ADDI, MUL: return 3'b000;
            MULH:      return 3'b001;
            MULHSU:    return 3'b010;
            MULHU:     return 3'b011;
            DIV:       return 3'b100;
            DIVU:      return 3'b101;
            REM:       return 3'b110;
            REMU:      return 3'b111;
            default:   return 3'b000;
        endcase
    endfunction

    function bit [6:0] get_funct7(instr_e op);
        case (op)
            MUL, MULH, MULHSU, MULHU,
            DIV, DIVU, REM, REMU: return 7'b0000001;
            default:              return 7'b0000000;
        endcase
    endfunction

endpackage

`else

package mul_int_test_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import tb_pkg::*;
    import mul_pkg::*;

    class mul_int_program;

        logic [31:0] code[$];
        instr_e      exp_op[$];
        logic [31:0] exp_result[$];
        string       name;

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

        static function mul_int_program get(string test_name);
            mul_int_program p = new();
            p.name = test_name;
            case (test_name)
                "mul_basic_test": begin
                    p.addi(1, 0, 3);
                    p.addi(2, 0, -2);
                    p.mul_op(MUL,  5, 1, 2, 32'hFFFF_FFFA);
                    p.lui (3, 20'h80000);
                    p.mul_op(MULH, 6, 3, 3, 32'h4000_0000);
                end
                "mul_all_ops_test": begin
                    p.addi(1, 0, 3);
                    p.addi(2, 0, -2);
                    p.lui (3, 20'h80000);
                    p.lui (4, 20'h80000);
                    p.addi(4, 4, -1);
                    p.addi(15, 0, -1);

                    p.mul_op(MUL,     5,  1,  2, 32'hFFFF_FFFA);
                    p.mul_op(MULH,    6,  3,  3, 32'h4000_0000);
                    p.mul_op(MULHSU,  7,  2,  2, 32'hFFFF_FFFE);
                    p.mul_op(MULHU,   8,  2,  2, 32'hFFFF_FFFC);

                    p.mul_op(MULH,    9,  4,  3, 32'hC000_0000);
                    p.mul_op(MULHU,  10, 15, 15, 32'hFFFF_FFFE);
                    p.mul_op(MULHSU, 11, 15, 15, 32'hFFFF_FFFF);
                    p.mul_op(MUL,    12, 15, 15, 32'h0000_0001);
                    p.mul_op(MUL,    13,  0,  2, 32'h0000_0000);

                    p.mul_op(MULH,   14,  3,  4, 32'hC000_0000);
                    p.mul_op(MUL,    16, 14,  1, 32'h4000_0000);
                    p.mul_op(MULHU,  17, 16, 16, 32'h1000_0000);
                    p.mul_op(MUL,    18, 17, 17, 32'h0000_0000);

                    p.addi(19, 0,  7);
                    p.addi(20, 0, -7);
                    p.addi(21, 0,  2);
                    p.addi(22, 0, -2);

                    p.mul_op(DIV, 23, 19, 21, 32'h0000_0003);
                    p.mul_op(DIV, 24, 20, 21, 32'hFFFF_FFFD);
                    p.mul_op(DIV, 25, 19, 22, 32'hFFFF_FFFD);
                    p.mul_op(DIV, 26, 20, 22, 32'h0000_0003);

                    p.mul_op(DIVU, 27,  2,  1, 32'h5555_5554);
                    p.mul_op(REM,  28, 20, 21, 32'hFFFF_FFFF);
                    p.mul_op(REM,  29, 19, 22, 32'h0000_0001);
                    p.mul_op(REMU, 30,  2,  1, 32'h0000_0002);

                    p.mul_op(DIV,  31, 19,  0, 32'hFFFF_FFFF);
                    p.mul_op(DIVU, 23,  2,  0, 32'hFFFF_FFFF);
                    p.mul_op(REM,  24, 19,  0, 32'h0000_0007);
                    p.mul_op(REMU, 25,  2,  0, 32'hFFFF_FFFE);

                    p.mul_op(DIV,  26,  3, 15, 32'h8000_0000);
                    p.mul_op(REM,  27,  3, 15, 32'h0000_0000);
                    p.mul_op(DIVU, 28, 15, 15, 32'h0000_0001);
                    p.mul_op(REMU, 29, 15, 15, 32'h0000_0000);

                    p.mul_op(DIV, 30, 19, 21, 32'h0000_0003);
                    p.mul_op(MUL, 31, 30, 19, 32'h0000_0015);
                end
                default: `uvm_fatal("MUL_INT_PROG", {"No program for test ", test_name})
            endcase

            return p;
        endfunction

    endclass

    class mul_int_expect_checker extends uvm_subscriber #(mul_seq_item);
        `uvm_component_utils(mul_int_expect_checker)

        mul_int_program prog;
        int unsigned    num_seen;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void write(mul_seq_item t);
            if (num_seen >= prog.exp_op.size()) begin
                `uvm_error("MUL_INT_CHK", {"Unexpected extra RV32M operation: ", t.convert2string()})
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
                `uvm_error("MUL_INT_CHK", $sformatf("Observed %0d RV32M operations, program contains %0d",
                    num_seen, prog.exp_op.size()))
        endfunction
    endclass

    class mul_int_base_test extends uvm_test;
        `uvm_component_utils(mul_int_base_test)

        mul_env                env;
        mul_int_expect_checker chk;
        mul_int_program        prog;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

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

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            fork
                wait (chk.num_seen == prog.exp_op.size());
                begin
                    #100us;
                    `uvm_error(get_type_name(), "Timeout waiting for the program's RV32M operations")
                end
            join_any
            disable fork;
            #200ns;
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

`endif
