`timescale 1ns/1ps

interface alu_mul_if (

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

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n;
        input id_valid, id_instr;
        input ex_mult_en, ex_mult_operand_a, ex_mult_operand_b;
        input ex_alu_en, ex_alu_operand_a, ex_alu_operand_b;
        input ex_valid;
        input ex_wb_we, ex_wb_waddr, ex_wb_wdata;
    endclocking

    modport MON (clocking mon_cb, input clk, input rst_n);

endinterface
