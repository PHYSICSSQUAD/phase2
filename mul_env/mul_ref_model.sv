//----------------------------------------------------------------------
// File       : mul_ref_model.sv
// Description: Golden (expected-value) model of the four RV32M
//              multiply instructions, written from the RISC-V
//              Unprivileged ISA spec, chapter 7.1:
//
//   MUL    : low  32 bits of rs1 x rs2
//   MULH   : high 32 bits of   signed(rs1) x   signed(rs2)
//   MULHSU : high 32 bits of   signed(rs1) x unsigned(rs2)
//   MULHU  : high 32 bits of unsigned(rs1) x unsigned(rs2)
//
// Why is it so simple?
// - It must be INDEPENDENT of the RTL. The RTL computes MULH* with a
//   5-cycle FSM of 16-bit partial products; copying that would copy its
//   bugs. Here we just extend both operands to 64 bits and let the
//   simulator multiply: different algorithm, same mathematical answer.
// - Why 64 bits? A 32x32 product needs up to 64 bits. Doing it in 32
//   bits would lose the high half that MULH* return.
// - Sign/zero extension is what makes the four instructions different:
//     signed   operand: copy bit 31 into bits 63..32 ($signed + longint)
//     unsigned operand: fill bits 63..32 with zeros
//   For MUL the low 32 bits are the same whatever extension is used.
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
        longint signed   a_s, b_s;   // sign-extended operands
        longint unsigned a_u, b_u;   // zero-extended operands
        logic   [63:0]   product;

        a_s = longint'($signed(rs1_val));   // e.g. 0xFFFFFFFF -> -1
        b_s = longint'($signed(rs2_val));
        a_u = {32'b0, rs1_val};             // e.g. 0xFFFFFFFF -> 4294967295
        b_u = {32'b0, rs2_val};

        case (op)
            MUL   : begin product = a_s * b_s; return product[31:0];  end
            MULH  : begin product = a_s * b_s; return product[63:32]; end
            // signed x unsigned: b_u fits in 63 bits, so a signed 64-bit
            // multiply with a zero-extended b gives the exact result.
            MULHSU: begin product = a_s * longint'(b_u); return product[63:32]; end
            MULHU : begin product = a_u * b_u; return product[63:32]; end
            default: begin
                `uvm_error(get_type_name(), $sformatf("predict() called with non-MUL op %s", op.name()))
                return 'x;
            end
        endcase
    endfunction

endclass
