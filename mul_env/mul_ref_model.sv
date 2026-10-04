//----------------------------------------------------------------------
// File       : mul_ref_model.sv
// Description: Golden (expected-value) model of the eight RV32M
//              multiply/divide instructions, written from the RISC-V
//              Unprivileged ISA spec, chapter 7:
//
//   MUL    : low  32 bits of rs1 x rs2
//   MULH   : high 32 bits of   signed(rs1) x   signed(rs2)
//   MULHSU : high 32 bits of   signed(rs1) x unsigned(rs2)
//   MULHU  : high 32 bits of unsigned(rs1) x unsigned(rs2)
//   DIV/U  : signed/unsigned quotient
//   REM/U  : signed/unsigned remainder
//
// Why is it so simple?
// - It must be INDEPENDENT of the RTL. The RTL computes MULH* with a
//   5-cycle FSM of 16-bit partial products; copying that would copy its
//   bugs. Here we just extend both operands to 64 bits and let the
//   simulator multiply: different algorithm, same mathematical answer.
// - Why 64 bits? A 32x32 product needs up to 64 bits. Doing it in 32
//   bits would lose the high half that MULH* return.
// - Sign/zero extension is what makes the four multiply instructions
//   different. The four divide instructions use native / and % after
//   signed/unsigned conversion. RISC-V divide-by-zero and signed
//   overflow are handled explicitly, before / or % is evaluated.
//
// Why a uvm_object (not a component)?
// - It has no ports, no phases and no state: it is a pure function. The
//   scoreboard owns one and calls predict(). (In the team env the
//   Predictor can call the same function.)
//
// Example (also in MUL_VERIFICATION_DESIGN.md):
//   MULH 0x80000000 x 0x80000000 = (-2^31) x (-2^31) = 2^62
//        = 0x4000_0000_0000_0000 -> expected rd = 0x40000000
//----------------------------------------------------------------------

class mul_ref_model extends uvm_object;

    `uvm_object_utils(mul_ref_model)

    function new(string name = "mul_ref_model");
        super.new(name);
    endfunction

    // Returns the value that must be written to rd.
    function logic [31:0] predict(instr_e op, logic [31:0] rs1_val, logic [31:0] rs2_val);
        longint signed    a_s, b_s;       // 64-bit sign-extended multiply operands
        longint unsigned  a_u, b_u;       // 64-bit zero-extended multiply operands
        logic signed [31:0] a32_s, b32_s; // signed divide operands
        logic        [63:0] product;

        a_s   = longint'($signed(rs1_val)); // e.g. 0xFFFFFFFF -> -1
        b_s   = longint'($signed(rs2_val));
        a_u   = {32'b0, rs1_val};           // e.g. 0xFFFFFFFF -> 4294967295
        b_u   = {32'b0, rs2_val};
        a32_s = rs1_val;
        b32_s = rs2_val;

        case (op)
            MUL   : begin product = a_s * b_s; return product[31:0];  end
            MULH  : begin product = a_s * b_s; return product[63:32]; end
            // signed x unsigned: b_u fits in 63 bits, so a signed 64-bit
            // multiply with a zero-extended b gives the exact result.
            MULHSU: begin product = a_s * longint'(b_u); return product[63:32]; end
            MULHU : begin product = a_u * b_u; return product[63:32]; end

            DIV: begin
                if (rs2_val == 32'b0) return 32'hFFFF_FFFF;
                // The only signed overflow case defined by RISC-V.
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
