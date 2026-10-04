class mul_env extends uvm_env;

    `uvm_component_utils(mul_env)

    mul_config     cfg;
    mul_agent      agent;
    mul_scoreboard sb;
    mul_coverage   cov;

    function new(string name = "mul_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(mul_config)::get(this, "", "mul_cfg", cfg)) begin
            cfg = mul_config::type_id::create("cfg");
            if (!uvm_config_db#(virtual alu_mul_if)::get(this, "", "alu_mul_vif", cfg.vif)) begin
                `uvm_fatal(get_type_name(), "Neither 'mul_cfg' nor 'alu_mul_vif' found in uvm_config_db (is alu_mul_bind.sv compiled and alu_mul_bind instantiated in tb_top?)")
            end
        end

        uvm_config_db#(mul_config)::set(this, "*", "mul_cfg", cfg);

        agent = mul_agent::type_id::create("agent", this);
        sb    = mul_scoreboard::type_id::create("sb", this);
        if (cfg.has_coverage) begin
            cov = mul_coverage::type_id::create("cov", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.ap.connect(sb.analysis_export);
        if (cfg.has_coverage) begin
            agent.ap.connect(cov.analysis_export);
        end
    endfunction

endclass
