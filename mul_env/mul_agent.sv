//----------------------------------------------------------------------
// File       : mul_agent.sv
// Description: Passive RV32M MUL/DIV agent = mul_config + virtual
//              interface + mul_monitor (the existing architecture box).
//
// Why an agent if it holds only a monitor?
// - It keeps the same structure as every other team agent, so the team
//   env treats all agents the same way. If later someone needs more
//   (e.g. a second monitor), only this file changes.
// - No sequencer and no driver are created: the agent is passive
//   because the multiplier's inputs come from the program the core
//   executes, not from us.
//
// Transaction flow:
//   mul_monitor.ap ---> (re-exported as) mul_agent.ap ---> env
//----------------------------------------------------------------------

class mul_agent extends uvm_agent;

    `uvm_component_utils(mul_agent)

    mul_monitor mon;
    mul_config  cfg;

    // Agent-level port: the env connects to agent.ap and does not need
    // to know the monitor exists inside.
    uvm_analysis_port #(mul_seq_item) ap;

    function new(string name = "mul_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(mul_config)::get(this, "", "mul_cfg", cfg)) begin
            `uvm_fatal(get_type_name(), "mul_config 'mul_cfg' not found in uvm_config_db")
        end
        // Always passive: see header.
        is_active = UVM_PASSIVE;
        mon = mul_monitor::type_id::create("mon", this);
    endfunction

    // connect_phase: hand out the monitor's port as the agent's port.
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        ap = mon.ap;
    endfunction

endclass
