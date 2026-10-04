class mul_agent extends uvm_agent;

    `uvm_component_utils(mul_agent)

    mul_monitor mon;
    mul_config  cfg;

    uvm_analysis_port #(mul_seq_item) ap;

    function new(string name = "mul_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(mul_config)::get(this, "", "mul_cfg", cfg)) begin
            `uvm_fatal(get_type_name(), "mul_config 'mul_cfg' not found in uvm_config_db")
        end

        is_active = UVM_PASSIVE;
        mon = mul_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        ap = mon.ap;
    endfunction

endclass
