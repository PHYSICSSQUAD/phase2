class mul_seq_item extends uvm_sequence_item;

    `uvm_object_utils(mul_seq_item)

    instr_t      instr;
    instr_e      op;
    logic [4:0]  rd;

    logic [31:0] rs1_val;
    logic [31:0] rs2_val;

    logic [31:0] result;
    logic        wb_we;
    logic [5:0]  wb_waddr;

    function new(string name = "mul_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("%-6s rd=x%0d rs1_val=0x%08h rs2_val=0x%08h result=0x%08h (instr=0x%08h we=%0b waddr=%0d)",
                         op.name(), rd, rs1_val, rs2_val, result,
                         instr.raw, wb_we, wb_waddr);
    endfunction

    function void do_copy(uvm_object rhs);
        mul_seq_item rhs_;
        if (!$cast(rhs_, rhs)) begin
            `uvm_fatal(get_type_name(), "do_copy: rhs is not a mul_seq_item")
        end
        super.do_copy(rhs);
        instr    = rhs_.instr;
        op       = rhs_.op;
        rd       = rhs_.rd;
        rs1_val  = rhs_.rs1_val;
        rs2_val  = rhs_.rs2_val;
        result   = rhs_.result;
        wb_we    = rhs_.wb_we;
        wb_waddr = rhs_.wb_waddr;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        mul_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return super.do_compare(rhs, comparer)  &&
               (instr.raw === rhs_.instr.raw)   &&
               (rs1_val   === rhs_.rs1_val)     &&
               (rs2_val   === rhs_.rs2_val)     &&
               (result    === rhs_.result)      &&
               (wb_we     === rhs_.wb_we)       &&
               (wb_waddr  === rhs_.wb_waddr);
    endfunction

endclass
