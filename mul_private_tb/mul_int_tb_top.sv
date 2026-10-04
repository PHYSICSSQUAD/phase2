//----------------------------------------------------------------------
// File       : mul_int_tb_top.sv
// Description: PRIVATE integration top for the RV32M MUL/DIV environment.
//
// - Instantiates the real cv32e40p_top and talks to it ONLY through
//   its top-level ports (no hierarchical references into the DUT).
// - The ALU_MUL interface is attached inside the core by the bind in
//   mul_env/alu_mul_bind.sv (one line below: "alu_mul_bind mul_bind();")
//   and registers itself in uvm_config_db, so this file never
//   connects any interface signal.
// - A minimal single-port memory answers both OBI buses (instruction
//   fetch and data) with grant in the same cycle and rvalid one cycle
//   later. It replaces the team's Instruction/Data agents, which are
//   not needed to validate the MUL environment.
//----------------------------------------------------------------------

`timescale 1ns/1ps

module mul_int_tb_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import mul_int_test_pkg::*;

    localparam int          MEM_WORDS = 1024;               // 4 KB at address 0
    localparam logic [31:0] JAL_SELF  = 32'h0000_006F;      // jal x0, 0

    logic clk   = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic [31:0] mem [0:MEM_WORDS-1];

    // ---------------- OBI signals ----------------
    logic        instr_req, instr_gnt, instr_rvalid;
    logic [31:0] instr_addr, instr_rdata;
    logic        data_req, data_gnt, data_rvalid, data_we;
    logic [3:0]  data_be;
    logic [31:0] data_addr, data_wdata, data_rdata;

    cv32e40p_top dut (
        .clk_i               (clk),
        .rst_ni              (rst_n),
        .pulp_clock_en_i     (1'b0),
        .scan_cg_en_i        (1'b0),
        .boot_addr_i         (32'h0000_0000),
        .mtvec_addr_i        (32'h0000_0000),
        .dm_halt_addr_i      (32'h0000_0000),
        .hart_id_i           (32'h0000_0000),
        .dm_exception_addr_i (32'h0000_0000),
        .instr_req_o         (instr_req),
        .instr_gnt_i         (instr_gnt),
        .instr_rvalid_i      (instr_rvalid),
        .instr_addr_o        (instr_addr),
        .instr_rdata_i       (instr_rdata),
        .data_req_o          (data_req),
        .data_gnt_i          (data_gnt),
        .data_rvalid_i       (data_rvalid),
        .data_we_o           (data_we),
        .data_be_o           (data_be),
        .data_addr_o         (data_addr),
        .data_wdata_o        (data_wdata),
        .data_rdata_i        (data_rdata),
        .irq_i               (32'h0),
        .irq_ack_o           (),
        .irq_id_o            (),
        .debug_req_i         (1'b0),
        .debug_havereset_o   (),
        .debug_running_o     (),
        .debug_halted_o      (),
        .fetch_enable_i      (1'b1),
        .core_sleep_o        ()
    );

    // ---------------- Attach the ALU_MUL interface (bind) ----------------
    // The only RV32M-monitor-related line in tb_top. It contains a "bind" that
    // puts alu_mul_if inside cv32e40p_core - see mul_env/alu_mul_bind.sv.
    alu_mul_bind mul_bind ();

    // ---------------- Simple OBI memory ----------------
    assign instr_gnt = instr_req;
    assign data_gnt  = data_req;

    // plain "always" (not always_ff): mem is also preloaded by the
    // initial block below
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instr_rvalid <= 1'b0;
            data_rvalid  <= 1'b0;
        end
        else begin
            instr_rvalid <= instr_req;
            if (instr_req) instr_rdata <= mem[instr_addr[11:2]];

            data_rvalid <= data_req;
            if (data_req) begin
                if (data_we) begin
                    for (int b = 0; b < 4; b++)
                        if (data_be[b]) mem[data_addr[11:2]][8*b +: 8] <= data_wdata[8*b +: 8];
                end
                else begin
                    data_rdata <= mem[data_addr[11:2]];
                end
            end
        end
    end

    // ---------------- Program load, reset, UVM start ----------------
    initial begin
        string          test_name;
        mul_int_program prog;

        if (!$value$plusargs("UVM_TESTNAME=%s", test_name)) test_name = "mul_all_ops_test";
        prog = mul_int_program::get(test_name);
        foreach (mem[i]) mem[i] = JAL_SELF;
        foreach (prog.code[i]) mem[i] = prog.code[i];
        $display("[mul_int_tb_top] loaded %0d instructions for %s", prog.code.size(), test_name);

        fork
            begin
                repeat (5) @(posedge clk);
                rst_n <= 1'b1;
            end
        join_none

        // Let every time-zero initial block run first. In particular, the
        // bound wrapper must put alu_mul_vif into uvm_config_db before UVM's
        // build_phase asks for it. This avoids simulator scheduling races.
        #0;
        run_test(test_name);
    end

endmodule
