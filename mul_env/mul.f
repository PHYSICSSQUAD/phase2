// Filelist of the MUL verification environment (paths relative to the
// repository root). Compile UVM and the RTL first, then:
//   vlog -sv -f mul_env/mul.f
// alu_mul_bind.sv binds the interface into cv32e40p_core, so the RTL
// must be part of the same simulation, and tb_top must contain
// ONE line:  alu_mul_bind mul_bind ();
// Free ModelSim (no covergroup licence): add +define+MUL_NO_COVERGROUP
-sv
+incdir+mul_env
shared_pkg/tb_pkg
mul_env/alu_mul_if.sv
mul_env/alu_mul_bind.sv
mul_env/mul_pkg.sv
