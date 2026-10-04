# RV32M MUL/DIV Verification Design

Environment that checks all eight RV32M arithmetic instructions (**MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU**) of the CV32E40P core. Existing `mul_*` names are kept for backward compatibility.
Folder: `mul_env/`. The guide is written for a junior verification engineer who needs to read, use or extend the environment.

---

## 28.1 Verification Objective

The goal is to prove that **every standard RV32M multiply, divide or remainder operation the core executes writes the correct 32-bit value to the correct destination register (`rd`)**.

For each executed RV32M arithmetic instruction we check three things:

1. The result equals the value defined by the RISC-V ISA spec (M extension, chapter 7), as computed by our own reference model.
2. The result is actually written (write enable = 1).
3. The result goes to the `rd` named in the instruction encoding.

## 28.2 Verification Scope

| In scope | Out of scope (and who owns it) |
|---|---|
| MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU (RV32M, funct7 = `0000001`, opcode `0110011`, funct3 `000` through `111`) | PULP/custom multiply (MAC, dot product, `p.mul*`) |
| Signed, unsigned and mixed operand handling | Whether `rs1_val`/`rs2_val` are the correct register values (forwarding, hazards) → Predictor / reg_file scoreboard |
| Low/high product, quotient and remainder | Register file content, including `rd = x0` staying 0 → reg_file scoreboard |
| Divide-by-zero and signed overflow (`MIN_INT / -1`) | Exact latency (MUL 1, MULH* 5, DIV/REM 3..35 cycles). Documented, not checked |
| Write-back enable and address of the result | PULP / custom arithmetic instructions excluded by the guidelines |
| Corner values (0, 1, -1, max positive, min negative) | Interrupts, debug, CSR, compressed and FP instructions → excluded by the guidelines |

## 28.3 Architecture

The team architecture (`tb_architecture/arch.jpg`) shows a **passive MUL agent** (Monitor + cfg + virtual interface) connected to the DUT through the shared **ALU_MUL interface**. That agent feeds the **ALU_MUL Scoreboard** and the **coverage_collector**. The same existing components now cover the standard RV32M divider too; names remain `mul_*` so existing integration does not break:

```text
tb_top
 ├── cv32e40p_top (DUT)          ← tb_top only touches its top-level ports
 │    └── core_i
 │         └── alu_mul_bind_i : alu_mul_bind_wrap   (added by "bind", no RTL edit)
 │              └── mul_if : alu_mul_if             (ALU_MUL interface)
 └── mul_bind : alu_mul_bind     (holds the bind statement - 1 line in tb_top)

uvm_test_top
 └── mul_env                         (small container, optional - see below)
      ├── agent : mul_agent          (PASSIVE - no driver, no sequencer)
      │     └── mon : mul_monitor    (reads alu_mul_if through mul_config.vif)
      ├── sb    : mul_scoreboard     (RV32M part of the ALU_MUL Scoreboard)
      │     └── ref_model : mul_ref_model (uvm_object, pure function)
      └── cov   : mul_coverage       (RV32M part of the coverage_collector)
```

| File | Purpose |
|---|---|
| `alu_mul_if.sv` | ALU_MUL interface. All ports are inputs; observes the multiplier, divider ALU operands and shared EX write port |
| `alu_mul_bind.sv` | `alu_mul_bind_wrap` (holds the interface and publishes it in `uvm_config_db` as `alu_mul_vif`) and `alu_mul_bind` (the `bind` into `cv32e40p_core`) |
| `mul_config.sv` | Config object: `vif`, `has_coverage` |
| `mul_seq_item.sv` | One observed RV32M multiply/divide/remainder instruction |
| `mul_monitor.sv` | Detects completed MUL/DIV operations and publishes items |
| `mul_agent.sv` | Passive agent that contains only the monitor |
| `mul_ref_model.sv` | Independent expected-value model |
| `mul_scoreboard.sv` | Predict + compare + summary |
| `mul_coverage.sv` | Functional coverage |
| `mul_env.sv` | Wires agent → scoreboard + coverage |
| `mul_pkg.sv` | Package that `include`s all the classes; imports `uvm_pkg` and `tb_pkg` |
| `mul.f` | Compile filelist |

`mul_env` is a convenience container. The team env can instantiate it as one block, or it can create `mul_agent` / `mul_scoreboard` / `mul_coverage` itself and copy the two `connect()` lines from `mul_env.sv`.

## 28.4 Transaction Flow

```text
DUT (core EX stage: multiplier or ALU divider)
 → alu_mul_if (bound inside the core, sampled by clocking block mon_cb)
 → mul_monitor   (detects "RV32M operation finishes now", builds mul_seq_item)
 → mul_seq_item  (instr, op, rd, rs1_val, rs2_val, result, wb_we, wb_waddr)
 → ap.write(item) ──┬──> mul_scoreboard.write(item)
                    │       → mul_ref_model.predict(op, rs1_val, rs2_val)
                    │       → compare expected vs item.result (+ we/waddr)
                    │       → PASS / MISMATCH
                    └──> mul_coverage.write(item) → mul_cg.sample()
```

`ap.write()` is a function call. The scoreboard and the coverage receive the **same item in the same simulation step**, without FIFOs or extra delay.

## 28.5 Component Responsibilities

- **alu_mul_if**: a window into the core. It reads signals and never drives them.
- **mul_config**: a bag of settings (interface handle, coverage on/off) handed to the agent via `uvm_config_db`. Optional: if no `mul_cfg` is set, `mul_env` builds one from the `alu_mul_vif` entry published by the bind wrapper.
- **mul_monitor**: watches every clock edge. It remembers which instruction entered EX and, when a supported RV32M operation finishes, packs everything into one transaction.
- **mul_agent**: a box around the monitor so the existing MUL agent looks like every other team agent. It is passive because the core runs its own program.
- **mul_ref_model**: answers "what should the result be?" with mathematical `*`, `/` and `%`, including explicit ISA special cases, independently of the RTL algorithms.
- **mul_scoreboard**: asks the reference model, compares, prints PASS/MISMATCH and prints a final summary. It warns if no supported RV32M operation was checked.
- **mul_coverage**: records which interesting cases (ops, signs, corner values, results) were exercised.

## 28.6 Important DUT Signals

How the RTL executes RV32M arithmetic (`cv32e40p_decoder`, `cv32e40p_id_stage`, `cv32e40p_ex_stage`, `cv32e40p_mult`, `cv32e40p_alu`, `cv32e40p_alu_div`):

- The decoder maps MUL to `MUL_MAC32`, which takes **1 cycle** in EX. MULH/MULHSU/MULHU map to `MUL_H` with `signed_mode` = 11/01/00 and take **5 cycles** in EX (FSM IDLE→STEP0→STEP1→STEP2→FINISH).
- DIV/DIVU/REM/REMU map to `ALU_DIV/ALU_DIVU/ALU_REM/ALU_REMU`. The serial ALU divider takes **3..35 cycles**. Its FSM is IDLE→DIVIDE→FINISH.
- The decoder swaps the ALU inputs for division: `alu_operand_a_ex` is architectural rs2 (divisor), and `alu_operand_b_ex` is rs1 (dividend). The monitor swaps them back into `item.rs1_val/rs2_val`.
- Results are written to the register file **from EX** through the shared ALU write port: multiplication selects `mult_result`; division selects the ALU's `result_div`.
- During multi-cycle iterations values are not final. Only the cycle where `ex_valid = 1` is checked.
- Instructions in EX are never flushed (branches resolve in EX and flush only IF/ID), so every operation that enters EX completes.

| Interface port | Core signal (bound in `cv32e40p_core`) | Why the monitor needs it |
|---|---|---|
| `clk` / `rst_n` | `clk` (gated core clock) / `rst_ni` | Clock of the ID/EX pipeline registers |
| `id_valid` | `id_valid` | Edge at which the ID instruction moves to EX |
| `id_instr` | `instr_rdata_id` | Real encoding, used to identify all 8 RV32M operations **independently of the DUT decoder** |
| `ex_mult_en` | `mult_en_ex` | A multiply is in EX |
| `ex_mult_operand_a/b` | `mult_operand_a_ex/_b_ex` | rs1/rs2 values seen by the multiplier |
| `ex_alu_en` | `alu_en_ex` | An ALU operation (including DIV/REM) is in EX |
| `ex_alu_operand_a/b` | `alu_operand_a_ex/_b_ex` | Decoder-swapped DIV/REM divisor/dividend |
| `ex_valid` | `ex_valid` | EX instruction finishes **now**, so the result is final |
| `ex_wb_we/_waddr/_wdata` | `regfile_alu_we_fw/_waddr_fw/_wdata_fw` | What is written to the register file, and where |

**Sampling rule** (clocking block `mon_cb`, `input #1step`, values just before the rising edge):

1. If `ex_valid`, the current EX instruction completes. The monitor publishes when either `ex_mult_en` is high, or the recorded encoding is DIV/REM and `ex_alu_en` is high. Normal ALU instructions are ignored.
2. If `id_valid`, the ID instruction enters EX, so the monitor records `id_instr`. This independent encoding later tells DIV from a normal ALU operation.

Step 1 runs before step 2 because back-to-back RV32M operations can leave and enter EX on the same edge.

**Latency** is not checked because legal stalls can make it longer than the nominal 1, 5 or 3..35 cycles.

**Connection to the DUT (bind).** The team only talks to the DUT through `cv32e40p_top`, but no top-level port carries the multiplier or divider result. `alu_mul_bind.sv` therefore uses a SystemVerilog `bind` to place the interface **inside** `cv32e40p_core` without editing any RTL file; the port connections use the core's local names, so tb_top has no hierarchical paths. tb_top needs exactly one line:

```systemverilog
alu_mul_bind mul_bind ();   // contains: bind cv32e40p_core alu_mul_bind_wrap alu_mul_bind_i (...);
```

The wrapper publishes the interface itself at time 0 (before `build_phase`):

```systemverilog
uvm_config_db#(virtual alu_mul_if)::set(null, "*", "alu_mul_vif", mul_if);
```

(An interface cannot pass a handle to itself, which is why a wrapper module is bound instead of the interface. A bind written alone at file level is ignored by ModelSim, which is why it sits inside module `alu_mul_bind`.)

## 28.7 Reference Model

Multiplying two 32-bit numbers gives up to a **64-bit** product, so the model works in 64 bits. The four instructions differ only in how each operand is widened from 32 to 64 bits:

| Instruction | rs1 widened as | rs2 widened as | Result bits |
|---|---|---|---|
| MUL | either (the low half is identical) | either | `[31:0]` |
| MULH | signed (copy bit 31) | signed | `[63:32]` |
| MULHSU | signed | unsigned (zeros) | `[63:32]` |
| MULHU | unsigned | unsigned | `[63:32]` |

Two's complement handles the sign: `$signed(32'hFFFFFFFF)` widened to `longint` is −1, while `{32'b0, 32'hFFFFFFFF}` is 4 294 967 295.

The RTL builds MULH* from 16-bit partial products over 5 cycles. The model does **not** copy that; it lets the simulator do one 64-bit multiply. Because the two algorithms differ, a bug in one is not repeated in the other.

Division uses 32-bit signed or unsigned `/` and `%`, not the RTL's serial shift/subtract algorithm:

| Instruction | Reference operation |
|---|---|
| DIV | signed quotient, truncated toward zero |
| DIVU | unsigned quotient |
| REM | signed remainder (sign follows rs1) |
| REMU | unsigned remainder |

RISC-V special cases are explicit: division by zero returns `FFFFFFFF`; remainder by zero returns rs1; `80000000 / FFFFFFFF` returns `80000000`; its remainder is zero.

## 28.8 Scoreboard

For every item, the scoreboard performs these steps inside `write()`:

```text
expected = ref_model.predict(op, rs1_val, rs2_val)
PASS  if result === expected  &&  wb_we === 1  &&  wb_waddr === {0, rd}
else  `uvm_error "MISMATCH" with instr, rs1, rs2, expected, actual, rd, we, waddr
```

- `===` makes X/Z on the DUT side a failure.
- No FIFOs are needed because operands and result arrive together in one item.
- `report_phase` prints totals and per-instruction counts.
- `check_phase` warns if the test executed zero supported RV32M operations, because a test with no checks proves nothing.

## 28.9 Coverage

| Item | Bins | Why |
|---|---|---|
| `cp_op` | All 8 MUL/DIV/REM operations | Every instruction runs at least once |
| `cp_rs1_class`, `cp_rs2_class` | zero, one, pos_other, max_pos (`7FFFFFFF`), min_neg (`80000000`), neg_other, minus_one (`FFFFFFFF`) | Arithmetic corner values; op × rs2 zero covers every divide-by-zero case |
| `cp_rs1_sign`, `cp_rs2_sign` | zero, msb_clear, msb_set | Signed and unsigned operations treat the MSB differently |
| `cx_op_sign` | op × rs1 sign × rs2 sign | Every op with every sign mix |
| `cx_op_rs1_class`, `cx_op_rs2_class` | op × corner value | Every corner value through every op |
| `cx_op_extremes` | op × {max_pos, min_neg, −1}² | Hardest pairs, including signed division overflow min_neg / −1 |
| `cx_op_result` | op × {zero, all_ones, other} | High/low result behaviour. MULHU × all_ones is an **ignore bin** because it is unreachable: the maximum MULHU result is `FFFFFFFE` |

## 28.10 Example Transaction

```text
Instruction : MULH x6, x1, x2     encoding 0x02209333
              (x1 = 0x80000000 = -2^31, x2 = 0x80000000 = -2^31)
    ↓
DUT execution: ID→EX edge: monitor records 0x02209333
               EX: MUL_H FSM runs 5 cycles; ex_valid = 1 only in FINISH
    ↓
Monitor transaction (completion edge):
               op=MULH rd=6 rs1_val=0x80000000 rs2_val=0x80000000
               result=<regfile_alu_wdata_fw> wb_we=1 wb_waddr=6
    ↓
Reference Model: (-2^31) × (-2^31) = 2^62 = 0x4000_0000_0000_0000
    ↓
Expected Result: bits [63:32] = 0x40000000
    ↓
Scoreboard    : result === 0x40000000 && we && waddr==6 → PASS, else MISMATCH
Meanwhile:
Monitor → Coverage: hits mulh, min_neg×min_neg, msb_set×msb_set, result "other"
```

A second example is MUL x5, x1, x2 with x1 = 3 and x2 = 0xFFFFFFFE (−2). The product is −6, so the expected result is `0xFFFFFFFA`.

For DIV x23, x19, x21 with x19=7 and x21=2, the decoder sends rs2 on EX ALU operand A and rs1 on operand B. The monitor swaps those back, the reference returns `7 / 2 = 3`, and the scoreboard checks data `00000003`, write enable and rd=23.

---

## Compilation

ModelSim-Intel FPGA Starter 10.5b, UVM 1.2. The DPI DLL is blocked on this machine, so UVM is compiled with `+define+UVM_NO_DPI` and run with `vsim -nodpiexports`.

```text
vlog -sv +define+UVM_NO_DPI +incdir+<uvm>/src <uvm>/src/uvm_pkg.sv
vlog -sv +incdir+<uvm>/src -f mul_env/mul.f          (run from the repo root)
```

The free ModelSim edition can **compile** covergroups, but it **refuses to elaborate** them because they need a Questa license. Compile `mul.f` with `+define+MUL_NO_COVERGROUP` on that edition (the coverage component then only counts received items). A full simulator (Questa, VCS or Xcelium) is needed to collect RV32M functional coverage.

## Private Integration Test (`mul_private_tb/`)

Private and temporary, as the spec requires: it is **not** part of the team environment. It proves that `mul_env` works on the real RTL.

- `mul_int_tb_top.sv`: `cv32e40p_top` connected only through its ports, a 4 KB OBI memory (grant in the same cycle, rvalid one cycle later), and `alu_mul_bind mul_bind();`.
- `mul_int_test_pkg.sv`: hand-written programs and a checker that compares every observed operation with a **hand-computed** value (independent of `mul_ref_model`), with two tests:
  - `mul_basic_test`: unchanged regression test with MUL and MULH.
  - `mul_all_ops_test`: 31 checks covering all 8 operations, multiply corners, all signed DIV sign pairs, unsigned DIV/REM, divide-by-zero, signed overflow, exact division, and DIV-result forwarding into MUL.
- `run.do`: compiles UVM, the RTL, `mul.f` and the TB, then runs.

```text
vsim -c -do "set FREE_MODELSIM 1; set TEST mul_all_ops_test; do mul_private_tb/run.do"
```

Current regression results with UVM 1.2 and `MUL_NO_COVERGROUP`:
- `mul_basic_test`: the unchanged multiply regression is 2/2 PASS.
- `mul_all_ops_test`: 31/31 PASS (MUL=6, MULH=3, MULHSU=2, MULHU=3, DIV=7, DIVU=3, REM=4, REMU=3).
- Both tests have 0 UVM_WARNING, 0 UVM_ERROR and 0 UVM_FATAL under Verilator 5.49.
- Full-design semantic compilation also passes with 0 errors both with and without the covergroup enabled (Slang 12.0).

## Known Limitations

- Operand correctness (forwarding and hazards) and `x0` semantics are left to the Predictor and reg_file scoreboard.
- Latency is not checked.
- Behaviour when reset is asserted in the middle of a MULH* or DIV/REM is not checked; the monitor simply discards the in-flight instruction.
- PULP multiply variants raise a `uvm_error` if they ever appear, but they are out of scope.
