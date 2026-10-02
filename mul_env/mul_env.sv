//----------------------------------------------------------------------
// File       : mul_env.sv
// Description: Small container that wires the MUL pieces together:
//
//      +------------------------- mul_env ---------------------------+
//      |  mul_agent (passive)                                        |
//      |   +-------------+                                           |
//      |   | mul_monitor |--ap--+--> mul_scoreboard (ref model)      |
//      |   +-------------+      |                                    |
//      |                        +--> mul_coverage (if has_coverage)  |
//      +-------------------------------------------------------------+
//
// Why a separate env?
// - It lets the MUL part be compiled, elaborated and tested on its own.
// - The team env can either instantiate mul_env as one block, OR create
//   mul_agent / mul_scoreboard / mul_coverage itself and copy the two
//   connect lines below (mapping them to the architecture's MUL agent,
//   ALU_MUL Scoreboard and coverage_collector).
//
// Configuration: someone above (test or team env) must do
//   uvm_config_db#(mul_config)::set(this, "<path to mul_env>*", "mul_cfg", cfg);
// If nobody did, this env builds a default config from the
// "alu_mul_vif" handle that the bind wrapper (alu_mul_bind.sv) publishes.
//----------------------------------------------------------------------

class mul_env extends uvm_env;

    `uvm_component_utils(mul_env)

    mul_config     cfg;
    mul_agent      agent;
    mul_scoreboard sb;
    mul_coverage   cov;

    function new(string name = "mul_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // build_phase (top-down): create children. Children's build_phase
    // runs after this one, so the config must be set before that.
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(mul_config)::get(this, "", "mul_cfg", cfg)) begin
            cfg = mul_config::type_id::create("cfg");
            if (!uvm_config_db#(virtual alu_mul_if)::get(this, "", "alu_mul_vif", cfg.vif)) begin
                `uvm_fatal(get_type_name(), "Neither 'mul_cfg' nor 'alu_mul_vif' found in uvm_config_db (is alu_mul_bind.sv compiled and alu_mul_bind instantiated in tb_top?)")
            end
        end
        // Make the same config visible to everything below this env.
        uvm_config_db#(mul_config)::set(this, "*", "mul_cfg", cfg);

        agent = mul_agent::type_id::create("agent", this);
        sb    = mul_scoreboard::type_id::create("sb", this);
        if (cfg.has_coverage) begin
            cov = mul_coverage::type_id::create("cov", this);
        end
    endfunction

    // connect_phase: one monitor port fans out to two subscribers.
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.ap.connect(sb.analysis_export);
        if (cfg.has_coverage) begin
            agent.ap.connect(cov.analysis_export);
        end
    endfunction

endclass
