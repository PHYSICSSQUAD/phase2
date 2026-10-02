# -----------------------------------------------------------------------------
# run.do - Compile and run the private UVM MUL integration test with Questa.
#
# From the project root (the directory containing mul_env/, rtl/, etc.), type:
#     do run.do
#
# Optional settings, entered before "do run.do":
#     set TEST mul_basic_test       ;# default: mul_all_ops_test
#     set UVM_SRC /path/to/uvm-1.2/src
#     set FREE_MODELSIM 1           ;# ModelSim Intel Starter only
#     set NO_DPI_EXPORTS 0          ;# enable DPI exports (requires a C/C++ compiler)
#     set EXIT_ON_DONE 1            ;# close Questa after the test (batch use)
#
# By default the script leaves Questa open and disables DPI exports, so
# Questa won't need an external C/C++ compiler for this SV-only testbench.
# UVM 1.2 is taken from UVM_SRC, UVM_HOME, or the simulator's MODEL_TECH path.
# -----------------------------------------------------------------------------

# Resolve the project root from this script, not from Questa's launch folder.
set _run_do [info script]
if {$_run_do eq ""} {
    set _run_do [file join [pwd] run.do]
}
set PROJECT_ROOT [file dirname [file normalize $_run_do]]
cd $PROJECT_ROOT

if {![info exists TEST]}           { set TEST mul_all_ops_test }
if {![info exists FREE_MODELSIM]}  { set FREE_MODELSIM 0 }
if {![info exists NO_DPI_EXPORTS]} { set NO_DPI_EXPORTS 1 }
if {![info exists EXIT_ON_DONE]}   { set EXIT_ON_DONE 0 }

if {[lsearch -exact {mul_basic_test mul_all_ops_test} $TEST] < 0} {
    error "Unknown TEST '$TEST'. Choose mul_basic_test or mul_all_ops_test."
}

# Find the UVM source directory. An explicit Tcl variable or environment
# variable takes priority, followed by common Questa/ModelSim install paths.
if {![info exists UVM_SRC]} { set UVM_SRC "" }
if {$UVM_SRC eq "" && [info exists env(UVM_SRC)]} {
    set UVM_SRC $env(UVM_SRC)
}
if {$UVM_SRC eq "" && [info exists env(UVM_HOME)]} {
    foreach _candidate [list [file join $env(UVM_HOME) src] $env(UVM_HOME)] {
        if {[file isfile [file join $_candidate uvm_pkg.sv]]} {
            set UVM_SRC $_candidate
            break
        }
    }
}
if {$UVM_SRC eq ""} {
    set _model_tech ""
    if {[info exists env(MODEL_TECH)]} {
        set _model_tech $env(MODEL_TECH)
    }
    if {$_model_tech eq "" && [info exists MODEL_TECH]} {
        set _model_tech $MODEL_TECH
    }
    if {$_model_tech ne ""} {
        foreach _candidate [list \
            [file join $_model_tech .. verilog_src uvm-1.2 src] \
            [file join $_model_tech .. uvm-1.2 src]] {
            if {[file isfile [file join $_candidate uvm_pkg.sv]]} {
                set UVM_SRC $_candidate
                break
            }
        }
    }
}
if {$UVM_SRC eq "" || ![file isfile [file join $UVM_SRC uvm_pkg.sv]]} {
    error "Cannot find UVM source (uvm_pkg.sv). Set UVM_SRC to the UVM 1.2 src directory, then run: do run.do"
}
set UVM_SRC [file normalize $UVM_SRC]
set UVM_INCLUDE [format {+incdir+%s} $UVM_SRC]

# Fail early with a useful message if a folder or source file wasn't copied.
foreach _required_file {
    shared_pkg/tb_pkg
    rtl/package/cv32e40p_apu_core_pkg.sv
    rtl/package/cv32e40p_fpu_pkg.sv
    rtl/package/cv32e40p_pkg.sv
    mul_env/mul.f
    mul_env/alu_mul_if.sv
    mul_env/alu_mul_bind.sv
    mul_env/mul_pkg.sv
    mul_private_tb/mul_int_test_pkg.sv
    mul_private_tb/mul_int_tb_top.sv
} {
    if {![file isfile $_required_file]} {
        error "Missing project file: [file join $PROJECT_ROOT $_required_file]"
    }
}

puts "============================================================"
puts "MUL UVM integration run"
puts "Project : $PROJECT_ROOT"
puts "UVM     : $UVM_SRC"
puts "Test    : $TEST"
if {$FREE_MODELSIM} {
    puts "Mode    : ModelSim Intel Starter (DPI and covergroups disabled)"
} else {
    puts "Mode    : Questa / full-featured ModelSim"
}
puts "============================================================"

# Start clean. The latch-based register file is an alternative module
# implementation with the same name, so only the FF version is compiled.
catch {quit -sim}
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# 1) UVM package.
if {$FREE_MODELSIM} {
    vlog -work work -sv +define+UVM_NO_DPI $UVM_INCLUDE [file join $UVM_SRC uvm_pkg.sv]
} else {
    vlog -work work -sv $UVM_INCLUDE [file join $UVM_SRC uvm_pkg.sv]
}

# 2) CV32E40P RTL packages, then RTL modules.
vlog -work work -sv \
    rtl/package/cv32e40p_apu_core_pkg.sv \
    rtl/package/cv32e40p_fpu_pkg.sv \
    rtl/package/cv32e40p_pkg.sv

set RTL_FILES {}
foreach _file [lsort [glob -nocomplain rtl/*.sv]] {
    if {[file tail $_file] ne "cv32e40p_register_file_latch.sv"} {
        lappend RTL_FILES $_file
    }
}
if {[llength $RTL_FILES] == 0} {
    error "No RTL source files found in [file join $PROJECT_ROOT rtl]."
}
eval vlog -work work -sv $RTL_FILES

# 3) MUL UVM environment and its bind/interface.
if {$FREE_MODELSIM} {
    vlog -work work -sv +define+MUL_NO_COVERGROUP $UVM_INCLUDE -f mul_env/mul.f
} else {
    vlog -work work -sv $UVM_INCLUDE -f mul_env/mul.f
}

# 4) Private integration test: a small program runs on the real RTL core.
vlog -work work -sv $UVM_INCLUDE \
    mul_private_tb/mul_int_test_pkg.sv \
    mul_private_tb/mul_int_tb_top.sv

# 5) Load and run. The testbench is SystemVerilog-only; its UVM/DUT checks
# do not use exported DPI functions. Disable automatic DPI export builds by
# default so Questa doesn't require an external C/C++ compiler (vsim-7019).
# Set NO_DPI_EXPORTS=0 only if your testbench needs DPI exports and a compiler
# is configured. The free ModelSim mode always uses -nodpiexports.
if {$FREE_MODELSIM || $NO_DPI_EXPORTS} {
    vsim -onfinish stop -nodpiexports work.mul_int_tb_top +UVM_TESTNAME=$TEST
} else {
    vsim -onfinish stop work.mul_int_tb_top +UVM_TESTNAME=$TEST
}
run -all

if {$EXIT_ON_DONE} {
    quit -f
}
