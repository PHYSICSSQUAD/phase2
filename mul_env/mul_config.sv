class mul_config extends uvm_object;

    `uvm_object_utils(mul_config)

    virtual alu_mul_if vif;

    uvm_active_passive_enum is_active = UVM_PASSIVE;

    bit has_coverage = 1;

    function new(string name = "mul_config");
        super.new(name);
    endfunction

endclass
