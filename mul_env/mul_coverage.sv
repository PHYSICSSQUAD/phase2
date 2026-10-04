class mul_coverage extends uvm_subscriber #(mul_seq_item);

    `uvm_component_utils(mul_coverage)

    mul_seq_item item;

`ifndef MUL_NO_COVERGROUP
    covergroup mul_cg;
        option.per_instance = 1;

        cp_op: coverpoint item.op {
            bins mul    = {MUL};
            bins mulh   = {MULH};
            bins mulhsu = {MULHSU};
            bins mulhu  = {MULHU};
            bins div    = {DIV};
            bins divu   = {DIVU};
            bins rem    = {REM};
            bins remu   = {REMU};
        }

        cp_rs1_class: coverpoint item.rs1_val {
            bins zero      = {32'h0000_0000};
            bins one       = {32'h0000_0001};
            bins pos_other = {[32'h0000_0002 : 32'h7FFF_FFFE]};
            bins max_pos   = {32'h7FFF_FFFF};
            bins min_neg   = {32'h8000_0000};
            bins neg_other = {[32'h8000_0001 : 32'hFFFF_FFFE]};
            bins minus_one = {32'hFFFF_FFFF};
        }
        cp_rs2_class: coverpoint item.rs2_val {
            bins zero      = {32'h0000_0000};
            bins one       = {32'h0000_0001};
            bins pos_other = {[32'h0000_0002 : 32'h7FFF_FFFE]};
            bins max_pos   = {32'h7FFF_FFFF};
            bins min_neg   = {32'h8000_0000};
            bins neg_other = {[32'h8000_0001 : 32'hFFFF_FFFE]};
            bins minus_one = {32'hFFFF_FFFF};
        }

        cp_rs1_sign: coverpoint item.rs1_val {
            bins zero      = {32'h0000_0000};
            bins msb_clear = {[32'h0000_0001 : 32'h7FFF_FFFF]};
            bins msb_set   = {[32'h8000_0000 : 32'hFFFF_FFFF]};
        }
        cp_rs2_sign: coverpoint item.rs2_val {
            bins zero      = {32'h0000_0000};
            bins msb_clear = {[32'h0000_0001 : 32'h7FFF_FFFF]};
            bins msb_set   = {[32'h8000_0000 : 32'hFFFF_FFFF]};
        }

        cp_rs1_extreme: coverpoint item.rs1_val {
            bins max_pos   = {32'h7FFF_FFFF};
            bins min_neg   = {32'h8000_0000};
            bins minus_one = {32'hFFFF_FFFF};
        }
        cp_rs2_extreme: coverpoint item.rs2_val {
            bins max_pos   = {32'h7FFF_FFFF};
            bins min_neg   = {32'h8000_0000};
            bins minus_one = {32'hFFFF_FFFF};
        }

        cp_result: coverpoint item.result {
            bins zero     = {32'h0000_0000};
            bins all_ones = {32'hFFFF_FFFF};
            bins other    = {[32'h0000_0001 : 32'hFFFF_FFFE]};
        }

        cx_op_sign      : cross cp_op, cp_rs1_sign, cp_rs2_sign;
        cx_op_rs1_class : cross cp_op, cp_rs1_class;
        cx_op_rs2_class : cross cp_op, cp_rs2_class;
        cx_op_extremes  : cross cp_op, cp_rs1_extreme, cp_rs2_extreme;

        cx_op_result    : cross cp_op, cp_result {

            ignore_bins mulhu_all_ones = binsof(cp_op.mulhu) && binsof(cp_result.all_ones);
        }
    endgroup
`endif

    int unsigned num_sampled;

    function new(string name = "mul_coverage", uvm_component parent = null);
        super.new(name, parent);
`ifndef MUL_NO_COVERGROUP

        mul_cg = new();
`endif
    endfunction

    function void write(mul_seq_item t);
        item = t;
        num_sampled++;
`ifndef MUL_NO_COVERGROUP
        mul_cg.sample();
`endif
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
`ifndef MUL_NO_COVERGROUP
        `uvm_info(get_type_name(),
            $sformatf("RV32M MUL/DIV functional coverage = %0.2f%% (%0d items sampled)",
                      mul_cg.get_inst_coverage(), num_sampled), UVM_NONE)
`else
        `uvm_info(get_type_name(),
            $sformatf("MUL_NO_COVERGROUP defined: covergroup disabled, %0d items received", num_sampled), UVM_NONE)
`endif
    endfunction

endclass
