//----------------------------------------------------------------------
// File       : mul_config.sv
// Description: Configuration object of the MUL agent.
//
// Why a config object?
// - It bundles everything the MUL agent needs (virtual interface and
//   knobs) in ONE object. The test/env puts it in uvm_config_db once;
//   the agent and monitor read it back. Same style as alu_config in
//   the team template.
// - It is a uvm_object (not a uvm_component) because it has no phases
//   and no place in the component tree - it is just data.
//----------------------------------------------------------------------

class mul_config extends uvm_object;

    `uvm_object_utils(mul_config)

    // Handle to the "ALU_MUL interface". "virtual" means: a reference to
    // the real interface instance that lives in tb_top (classes cannot
    // contain interfaces, only handles to them).
    virtual alu_mul_if vif;

    // The MUL agent is always passive in our architecture (the core is
    // driven by the Instruction/Data agents, not by us). It is kept as a
    // field only so the agent code reads like the other team agents.
    uvm_active_passive_enum is_active = UVM_PASSIVE;

    // 1 = create the MUL coverage collector. A regression can set it to
    // 0 to save simulation time without touching code.
    bit has_coverage = 1;

    function new(string name = "mul_config");
        super.new(name);
    endfunction

endclass
