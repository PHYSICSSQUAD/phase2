//----------------------------------------------------------------------
// File       : mul_pkg.sv
// Description: UVM package of the RV32M MUL/DIV verification environment.
//              Everything class-based for MUL/DIV lives here, so other
//              packages/tests only need "import mul_pkg::*;".
//
// Why `include instead of separate packages?
// - Same style as the team template (alu_pkg). One package = one
//   compile unit; include order = dependency order.
// - The include paths are relative to this file's folder, so compile
//   with +incdir+<repo>/mul_env (see mul.f).
//
// Note: alu_mul_if.sv is NOT included: interfaces are compiled
// separately (they are not allowed inside a package).
//----------------------------------------------------------------------

package mul_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Shared team package: instr_t, instr_e, get_opcode/funct3/funct7.
    import tb_pkg::*;

    // --- Foundation ---
    `include "mul_config.sv"
    `include "mul_seq_item.sv"

    // --- Agent ---
    `include "mul_monitor.sv"
    `include "mul_agent.sv"

    // --- Analysis ---
    `include "mul_ref_model.sv"
    `include "mul_scoreboard.sv"
    `include "mul_coverage.sv"

    // --- Container ---
    `include "mul_env.sv"

endpackage
