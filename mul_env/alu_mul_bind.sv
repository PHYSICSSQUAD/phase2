//----------------------------------------------------------------------
// File       : alu_mul_bind.sv
// Description: Attaches the "ALU_MUL interface" to the CV32E40P core
//              with a SystemVerilog "bind" statement.
//
// Why bind?
// - Our testbench may only talk to the DUT through cv32e40p_top. But
//   the guidelines also ask for scoreboards "in the datapath" to make
//   debugging easy, and the multiplier result never appears on a
//   cv32e40p_top port.
// - "bind <module> <unit> <instance> (...)" asks the simulator to add
//   <unit> INSIDE every instance of <module>, as if it had been written
//   in the RTL - without editing any RTL file. The port connections
//   are evaluated inside cv32e40p_core, so they use the core's own
//   local signal names and need no hierarchical paths.
// - We bind a tiny wrapper MODULE (alu_mul_bind_wrap) instead of the
//   interface itself: the wrapper instantiates alu_mul_if and puts its
//   handle into uvm_config_db as "alu_mul_vif". (An interface cannot
//   pass a handle to itself, but its parent module can.)
// - tb_top therefore has no "dut.core_i...." references and does not
//   connect any interface signal itself.
//
// How to use: compile this file with the RTL (it is listed in mul.f)
// and add ONE line to tb_top:
//       alu_mul_bind mul_bind ();
// The bind statement is placed inside module "alu_mul_bind" because
// simulators (e.g. ModelSim) only apply a bind that belongs to an
// elaborated module; a bind left alone in a file may be ignored.
// (Alternative: load alu_mul_bind as a second top: vsim tb_top alu_mul_bind)
//
// Signal sources (all declared in cv32e40p_core.sv):
//   clk                  : gated core clock - the clock of all ID/EX
//                          pipeline registers (it stops when the core
//                          sleeps, so the monitor sees no fake edges).
//   id_valid             : ID stage hands its instruction to EX
//   instr_rdata_id       : instruction word currently in ID
//   mult_en_ex           : ID/EX register - multiplier instruction in EX
//   mult_operand_a/b_ex  : ID/EX registers - rs1/rs2 values
//   ex_valid             : EX instruction finishes this cycle
//   regfile_alu_*_fw     : EX write-back port to the register file
//----------------------------------------------------------------------

`timescale 1ns/1ps

module alu_mul_bind_wrap (
    input logic        clk,
    input logic        rst_n,
    input logic        id_valid,
    input logic [31:0] id_instr,
    input logic        ex_mult_en,
    input logic [31:0] ex_mult_operand_a,
    input logic [31:0] ex_mult_operand_b,
    input logic        ex_valid,
    input logic        ex_wb_we,
    input logic [5:0]  ex_wb_waddr,
    input logic [31:0] ex_wb_wdata
);
    import uvm_pkg::*;

    alu_mul_if mul_if (.*);

    // Runs at time 0 with no delay, i.e. before UVM's build_phase
    // (run_test only starts phasing after some #0 delays).
    initial uvm_config_db#(virtual alu_mul_if)::set(null, "*", "alu_mul_vif", mul_if);
endmodule

module alu_mul_bind;
bind cv32e40p_core alu_mul_bind_wrap alu_mul_bind_i (
    .clk               (clk),
    .rst_n             (rst_ni),
    .id_valid          (id_valid),
    .id_instr          (instr_rdata_id),
    .ex_mult_en        (mult_en_ex),
    .ex_mult_operand_a (mult_operand_a_ex),
    .ex_mult_operand_b (mult_operand_b_ex),
    .ex_valid          (ex_valid),
    .ex_wb_we          (regfile_alu_we_fw),
    .ex_wb_waddr       (regfile_alu_waddr_fw),
    .ex_wb_wdata       (regfile_alu_wdata_fw)
);
endmodule
