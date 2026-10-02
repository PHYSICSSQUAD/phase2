# ---------------------------------------------------------------------
# run.do - PRIVATE MUL integration test (ModelSim / Questa)
#
# Run from the REPOSITORY ROOT:
#   vsim -c -do "set TEST mul_basic_test; do mul_private_tb/run.do"
#   vsim -c -do "set TEST mul_all_ops_test; do mul_private_tb/run.do"
#
# Options (set before "do"):
#   TEST          mul_basic_test (default) | mul_all_ops_test
#   FREE_MODELSIM 1 = free ModelSim-Intel edition:
#                   - UVM compiled with UVM_NO_DPI, vsim -nodpiexports
#                   - +define+MUL_NO_COVERGROUP (no covergroup licence)
#   UVM_SRC       UVM 1.2 source dir (default: the simulator's copy)
# ---------------------------------------------------------------------

if {![info exists TEST]}          {set TEST mul_basic_test}
if {![info exists FREE_MODELSIM]} {set FREE_MODELSIM 0}
if {![info exists UVM_SRC]}       {set UVM_SRC $env(MODEL_TECH)/../verilog_src/uvm-1.2/src}

if {$FREE_MODELSIM} {
    set UVM_DEFS  "+define+UVM_NO_DPI"
    set COV_DEFS  "+define+MUL_NO_COVERGROUP"
    set VSIM_OPTS "-nodpiexports"
} else {
    set UVM_DEFS  ""
    set COV_DEFS  ""
    set VSIM_OPTS ""
}

if {[file exists work]} {vdel -lib work -all}
vlib work

# 1. UVM
eval vlog -sv $UVM_DEFS +incdir+$UVM_SRC $UVM_SRC/uvm_pkg.sv

# 2. RTL (packages first; the latch register file is an alternative
#    implementation of the same module, so only the FF one is used)
vlog -sv rtl/package/cv32e40p_apu_core_pkg.sv rtl/package/cv32e40p_fpu_pkg.sv rtl/package/cv32e40p_pkg.sv
set RTL_FILES {}
foreach f [lsort [glob rtl/*.sv]] {
    if {![string match *register_file_latch* $f]} {lappend RTL_FILES $f}
}
eval vlog -sv $RTL_FILES

# 3. MUL environment (team code) - includes the bind
eval vlog -sv $COV_DEFS +incdir+$UVM_SRC -f mul_env/mul.f

# 4. Private integration TB
vlog -sv +incdir+$UVM_SRC mul_private_tb/mul_int_test_pkg.sv mul_private_tb/mul_int_tb_top.sv

eval vsim -c $VSIM_OPTS work.mul_int_tb_top +UVM_TESTNAME=$TEST
run -all
quit -f
