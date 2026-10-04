class mul_ref_model extends uvm_object;

    `uvm_object_utils(mul_ref_model)

    function new(string name = "mul_ref_model");
        super.new(name);
    endfunction

    function logic [31:0] predict(instr_e op, logic [31:0] rs1_val, logic [31:0] rs2_val);
        longint signed    a_s, b_s;
        longint unsigned  a_u, b_u;
        logic signed [31:0] a32_s, b32_s;
        logic        [63:0] product;

        a_s   = longint'($signed(rs1_val));
        b_s   = longint'($signed(rs2_val));
        a_u   = {32'b0, rs1_val};
        b_u   = {32'b0, rs2_val};
        a32_s = rs1_val;
        b32_s = rs2_val;

        case (op)
            MUL   : begin product = a_s * b_s; return product[31:0];  end
            MULH  : begin product = a_s * b_s; return product[63:32]; end

            MULHSU: begin product = a_s * longint'(b_u); return product[63:32]; end
            MULHU : begin product = a_u * b_u; return product[63:32]; end

            DIV: begin
                if (rs2_val == 32'b0) return 32'hFFFF_FFFF;

                if (rs1_val == 32'h8000_0000 && rs2_val == 32'hFFFF_FFFF)
                    return 32'h8000_0000;
                return a32_s / b32_s;
            end
            DIVU: begin
                if (rs2_val == 32'b0) return 32'hFFFF_FFFF;
                return rs1_val / rs2_val;
            end
            REM: begin
                if (rs2_val == 32'b0) return rs1_val;
                if (rs1_val == 32'h8000_0000 && rs2_val == 32'hFFFF_FFFF)
                    return 32'b0;
                return a32_s % b32_s;
            end
            REMU: begin
                if (rs2_val == 32'b0) return rs1_val;
                return rs1_val % rs2_val;
            end

            default: begin
                `uvm_error(get_type_name(), $sformatf("predict() called with non-RV32M op %s", op.name()))
                return 'x;
            end
        endcase
    endfunction

endclass
