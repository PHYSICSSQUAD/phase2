# -----------------------------------------------------------------------------
# run.do - Standalone Questa integration run for the RV32M MUL/DIV environment
#
# Required project layout (no shared_pkg folder is needed):
#
#   your_project/
#     mul_env/
#     mul_private_tb/
#     rtl/
#
# Run Questa from your_project or from your_project/mul_private_tb. The script
# searches upward from the current directory. PROJECT_ROOT can override it.
#
# GUI, run the complete test and keep the simulation open:
#   set TEST mul_all_ops_test
#   set KEEP_OPEN 1
#   do mul_private_tb/run.do
#
# GUI, run both tests:
#   set TEST all
#   set KEEP_OPEN 1
#   do mul_private_tb/run.do
#
# Command line, run both tests and exit:
#   vsim -c -do "set TEST all; set KEEP_OPEN 0; do mul_private_tb/run.do"
#
# Options set before "do":
#   TEST          mul_basic_test | mul_all_ops_test (default) | all
#   COVERAGE      0 (default) = portable mode for licenses without
#                 svverification; disables covergroups and code coverage
#                 1 = enable full Questa coverage and save UCDB files
#   KEEP_OPEN     0 (default) = close Questa after the run (command-line mode)
#                 1 = leave the last simulation open for GUI debug
#   PROJECT_ROOT  Optional starting folder for the upward search. It may be the
#                 project root or its mul_private_tb subfolder.
#   UVM_SRC       UVM 1.2 src directory. Normally found automatically.
#   UVM_VERBOSITY UVM_LOW (default), UVM_MEDIUM, UVM_HIGH, ...
#
# Notes:
# - UVM is compiled with UVM_NO_DPI. The test needs no DPI library and is more
#   portable between Windows and Linux Questa installations.
# - A private, minimal tb_pkg is compiled from mul_int_test_pkg.sv first. It
#   replaces the missing shared_pkg only for this standalone three-folder run.
# - Only cv32e40p_register_file_ff.sv is compiled. The latch register-file file
#   implements the same module and must not be compiled at the same time.
# -----------------------------------------------------------------------------

if {![info exists TEST]}          {set TEST mul_all_ops_test}
if {![info exists COVERAGE]}      {set COVERAGE 0}
if {![info exists KEEP_OPEN]}     {set KEEP_OPEN 0}
if {![info exists UVM_VERBOSITY]} {set UVM_VERBOSITY UVM_LOW}

# Return 1 only for the project folder that contains the complete three-folder
# layout. Do not use "info script" here: some Questa versions report an
# internal path such as /mtitcl/vsim instead of the real .do file path.
proc mul_has_project_layout {candidate} {
    foreach required_dir {mul_env mul_private_tb rtl rtl/package} {
        if {![file isdirectory [file join $candidate $required_dir]]} {
            return 0
        }
    }
    return 1
}

# Treat PROJECT_ROOT as the first search location, not only as an exact match.
# This means PROJECT_ROOT=[pwd] also works when Questa was started from inside
# mul_private_tb; the search then moves one level up to the real project root.
set ROOT_DIR ""
set ROOT_CANDIDATES {}
if {[info exists PROJECT_ROOT]} {
    lappend ROOT_CANDIDATES $PROJECT_ROOT
}
lappend ROOT_CANDIDATES [pwd]
if {[info exists env(PWD)]} {
    lappend ROOT_CANDIDATES $env(PWD)
}

foreach starting_dir $ROOT_CANDIDATES {
    set candidate [file normalize $starting_dir]
    for {set level 0} {$level < 6} {incr level} {
        if {[mul_has_project_layout $candidate]} {
            set ROOT_DIR $candidate
            break
        }
        set parent [file dirname $candidate]
        if {$parent eq $candidate} {
            break
        }
        set candidate $parent
    }
    if {$ROOT_DIR ne ""} {
        break
    }
}

if {$ROOT_DIR eq "" || ![mul_has_project_layout $ROOT_DIR]} {
    error "Cannot find the project folder. Run Questa from the folder containing mul_env, mul_private_tb and rtl, or set PROJECT_ROOT explicitly before do. Tcl pwd=[pwd]"
}
cd $ROOT_DIR

puts ""
puts "============================================================"
puts " RV32M private integration test"
puts " Project root : $ROOT_DIR"
puts " Test         : $TEST"
puts " Coverage     : $COVERAGE"
puts "============================================================"
puts ""

# Find the UVM 1.2 source shipped with Questa. The user may override this by
# setting UVM_SRC before running the script.
if {![info exists UVM_SRC]} {
    set UVM_CANDIDATES {}

    if {[info exists env(UVM_HOME)]} {
        lappend UVM_CANDIDATES [file join $env(UVM_HOME) src]
        lappend UVM_CANDIDATES $env(UVM_HOME)
    }
    if {[info exists env(QUESTA_HOME)]} {
        lappend UVM_CANDIDATES [file join $env(QUESTA_HOME) verilog_src uvm-1.2 src]
    }
    if {[info exists env(MODEL_TECH)]} {
        lappend UVM_CANDIDATES [file join $env(MODEL_TECH) .. verilog_src uvm-1.2 src]
    }
    if {[info exists env(MTI_HOME)]} {
        lappend UVM_CANDIDATES [file join $env(MTI_HOME) verilog_src uvm-1.2 src]
    }

    foreach candidate $UVM_CANDIDATES {
        set candidate [file normalize $candidate]
        if {[file isfile [file join $candidate uvm_pkg.sv]]} {
            set UVM_SRC $candidate
            break
        }
    }
}

if {![info exists UVM_SRC] || ![file isfile [file join $UVM_SRC uvm_pkg.sv]]} {
    error "UVM 1.2 was not found. Set UVM_SRC to the directory that contains uvm_pkg.sv, then run this script again."
}
set UVM_SRC [file normalize $UVM_SRC]
puts "Using UVM_SRC: $UVM_SRC"

# TEST may select one test or a two-test regression.
switch -- $TEST {
    mul_basic_test   {set TEST_LIST {mul_basic_test}}
    mul_all_ops_test {set TEST_LIST {mul_all_ops_test}}
    all              {set TEST_LIST {mul_basic_test mul_all_ops_test}}
    default {
        error "Unknown TEST '$TEST'. Use mul_basic_test, mul_all_ops_test, or all."
    }
}

# Start from a clean library. Unload a previous run first so the script can be
# executed again from the same GUI session.
catch {quit -sim}
if {[file exists work]} {
    catch {vdel -lib work -all}
    file delete -force work
}
vlib work

# -----------------------------------------------------------------------------
# 1. UVM 1.2. UVM_NO_DPI removes the platform-specific C/DPI dependency.
# -----------------------------------------------------------------------------
set CMD [list vlog -sv -work work "+define+UVM_NO_DPI" "+incdir+$UVM_SRC" [file join $UVM_SRC uvm_pkg.sv]]
puts "\n-- Compiling UVM 1.2"
eval $CMD

# -----------------------------------------------------------------------------
# 2. Small standalone tb_pkg from the existing private-test file.
#    This first pass compiles only instruction types and encoding helpers.
# -----------------------------------------------------------------------------
set CMD [list vlog -sv -work work "+define+MUL_PRIVATE_TB_TYPES" [file join mul_private_tb mul_int_test_pkg.sv]]
puts "\n-- Compiling standalone instruction types"
eval $CMD

# -----------------------------------------------------------------------------
# 3. CV32E40P RTL: packages first, then modules. Do not compile both register
#    file implementations because both files define cv32e40p_register_file.
# -----------------------------------------------------------------------------
set RTL_PACKAGES [list \
    [file join rtl package cv32e40p_apu_core_pkg.sv] \
    [file join rtl package cv32e40p_fpu_pkg.sv] \
    [file join rtl package cv32e40p_pkg.sv]]

set CMD [list vlog -sv -work work]
if {$COVERAGE} {lappend CMD -cover bcesft}
foreach f $RTL_PACKAGES {lappend CMD $f}
puts "\n-- Compiling RTL packages"
eval $CMD

set RTL_FILES {}
foreach f [lsort [glob [file join rtl *.sv]]] {
    if {![string match *register_file_latch.sv $f]} {
        lappend RTL_FILES $f
    }
}

set CMD [list vlog -sv -work work]
if {$COVERAGE} {lappend CMD -cover bcesft}
foreach f $RTL_FILES {lappend CMD $f}
puts "\n-- Compiling RTL modules"
eval $CMD

# -----------------------------------------------------------------------------
# 4. RV32M UVM environment. Compile explicitly instead of mul.f because mul.f
#    is the normal team filelist and expects shared_pkg/tb_pkg.
# -----------------------------------------------------------------------------
set CMD [list vlog -sv -work work "+incdir+$UVM_SRC" "+incdir+[file join $ROOT_DIR mul_env]"]
if {!$COVERAGE} {lappend CMD "+define+MUL_NO_COVERGROUP"}
lappend CMD \
    [file join mul_env alu_mul_if.sv] \
    [file join mul_env alu_mul_bind.sv] \
    [file join mul_env mul_pkg.sv]
puts "\n-- Compiling RV32M MUL/DIV environment"
eval $CMD

# -----------------------------------------------------------------------------
# 5. Private test package and top. This second compile of mul_int_test_pkg.sv
#    has no MUL_PRIVATE_TB_TYPES define, so it builds the actual UVM tests.
# -----------------------------------------------------------------------------
set CMD [list vlog -sv -work work "+incdir+$UVM_SRC" \
    [file join mul_private_tb mul_int_test_pkg.sv] \
    [file join mul_private_tb mul_int_tb_top.sv]]
puts "\n-- Compiling private integration tests"
eval $CMD

# -----------------------------------------------------------------------------
# 6. Simulate. TEST=all reuses the compiled library for both tests.
# -----------------------------------------------------------------------------
if {$COVERAGE} {
    set OUT_DIR [file join $ROOT_DIR questa_out]
    file mkdir $OUT_DIR
}

set TEST_INDEX 0
foreach CURRENT_TEST $TEST_LIST {
    incr TEST_INDEX
    puts ""
    puts "============================================================"
    puts " Running $CURRENT_TEST"
    puts "============================================================"

    set CMD [list vsim]
    if {$COVERAGE} {
        lappend CMD -coverage
    } else {
        # Questa-Intel/limited licenses need this at elaboration as well as
        # MUL_NO_COVERGROUP at compilation.
        lappend CMD -nocvg -nodpiexports
    }
    lappend CMD -voptargs=+acc work.mul_int_tb_top \
        "+UVM_TESTNAME=$CURRENT_TEST" "+UVM_VERBOSITY=$UVM_VERBOSITY"
    eval $CMD

    run -all

    if {$COVERAGE} {
        set UCDB_FILE [file join $OUT_DIR "$CURRENT_TEST.ucdb"]
        coverage save $UCDB_FILE
        puts "Coverage database: $UCDB_FILE"
    }

    # Unload every simulation except the last one when the user wants to
    # inspect it in the GUI.
    if {$TEST_INDEX < [llength $TEST_LIST] || !$KEEP_OPEN} {
        quit -sim
    }
}

puts ""
puts "============================================================"
puts " Regression finished. Check the UVM summary for zero errors."
if {$COVERAGE} {puts " UCDB files are in: [file join $ROOT_DIR questa_out]"}
puts "============================================================"
puts ""

if {!$KEEP_OPEN} {
    quit -force
}
