`timescale 1ns/1ps

module alu_mul_bind_wrap (
    input logic        clk,
    input logic        rst_n,
    input logic        id_valid,
    input logic [31:0] id_instr,
    input logic        ex_mult_en,
    input logic [31:0] ex_mult_operand_a,
    input logic [31:0] ex_mult_operand_b,
    input logic        ex_alu_en,
    input logic [31:0] ex_alu_operand_a,
    input logic [31:0] ex_alu_operand_b,
    input logic        ex_valid,
    input logic        ex_wb_we,
    input logic [5:0]  ex_wb_waddr,
    input logic [31:0] ex_wb_wdata
);
    import uvm_pkg::*;

    alu_mul_if mul_if (.*);

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
    .ex_alu_en         (alu_en_ex),
    .ex_alu_operand_a  (alu_operand_a_ex),
    .ex_alu_operand_b  (alu_operand_b_ex),
    .ex_valid          (ex_valid),
    .ex_wb_we          (regfile_alu_we_fw),
    .ex_wb_waddr       (regfile_alu_waddr_fw),
    .ex_wb_wdata       (regfile_alu_wdata_fw)
);
endmodule
