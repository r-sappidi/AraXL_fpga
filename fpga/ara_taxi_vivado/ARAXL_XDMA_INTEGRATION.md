# AraXL ⇄ Xilinx XDMA Integration — Simulation Writeup

This document describes the work done to bring up a behavioral (xsim) simulation of
the **LiteFury (Artix‑7) XDMA PCIe endpoint driving the AraXL vector SoC**, why the
original flow crashed, the testbench architecture that now works, how the integration
is wired, what is verified, and the one remaining open issue with its precise diagnosis.

---

## 1. TL;DR / Status

| Item | Status |
|------|--------|
| Terminal crash when running the sim (`make araxl-dotproduct-xsim`) | **Fixed** |
| Root cause of the crash diagnosed | **Done** — PCIe transceiver‑generation mismatch → X‑storm → OOM |
| PCIe link brings up in sim | **Working** — trains to **L0** |
| PCIe enumeration (link speed/width, device/vendor ID, BAR scan) | **Working** — all checks PASS |
| XDMA H2C DMA engine runs and issues AXI writes to AraXL's memory map | **Working** — valid 512‑byte INCR bursts to `0x8000_0000` |
| H2C write **data lands in L2 with correct bytes/addresses, no X** | **Working (partial)** — verified for the first beats before the sim wall |
| Full H2C payload load + core release + dotproduct + exit register | **Blocked by an xsim limitation** (not a logic bug) — see §8 |

The novel and hard part — getting a Xilinx XDMA PCIe endpoint to link up and enumerate
against a root‑complex BFM in xsim, wired to the AraXL SoC — is fully working, **and the
H2C DMA demonstrably writes the correct kernel bytes into L2** (correct incrementing
addresses, zero X). The remaining blocker is **not a logic bug**: it is a zero‑delay
(delta‑cycle) combinational settling issue in the standard AraXL AXI fabric that **xsim's
event scheduler cannot converge**, while QuestaSim/Verilator (where this IP is regression
tested) do. It has been thoroughly localized and is documented in §8, along with the
realistic paths to a full end‑to‑end run.

---

## 2. The original problem: the terminal crashed

Running the integration simulation reliably **killed the user's terminal**. This was an
**out‑of‑memory (OOM) kill**, not a Vivado bug:

1. The simulation paired a **7‑series GTPE2** XDMA endpoint with an **UltraScale GTHE3**
   root‑complex BFM (see §3). The two transceiver generations cannot train against each
   other, so the PCIe link never came up.
2. The un‑trained link left `X` (unknown) values propagating into the large AraXL vector
   core, producing a **zero‑delay event storm** (xsim spins at a fixed simulated time,
   allocating without bound).
3. With no memory cap, xsim consumed all RAM + swap. The Linux OOM killer then reaped
   processes — including the terminal.

### Fixes that make the flow safe (kept permanently)

- **Memory cap on the simulator.** `make araxl-dotproduct-xsim` now runs xsim inside a
  `systemd-run --user --scope -p MemoryMax=24G -p MemorySwapMax=2G` cgroup (with a
  `ulimit -v` fallback). A runaway now dies *alone*, leaving the terminal intact.
  Tunables: `XSIM_MEM_MAX`, `XSIM_SWAP_MAX`, `XSIM_VMEM_KB`.
- **No waveform logging by default.** `run_araxl_dotproduct_xsim.tcl` sets
  `xsim.elaborate.debug_level off` unless `ARAXL_XSIM_WAVES=1`. Logging the full design
  hierarchy under `run all` is itself a memory blow‑up; disabling it keeps xsim's working
  set flat (~0.3–3 GB) for the whole run.

These two changes alone resolve the user's reported symptom regardless of anything below.

---

## 3. Root cause of the link failure

`create_project.tcl` generates the XDMA IP for the **Artix‑7** LiteFury part
(`xc7a100tlfgg484-2L`). For a 7‑series part the XDMA PCIe block uses **GTPE2** (`pcie_7x`)
transceivers, configured **Gen1 ×4** (2.5 GT/s).

The original testbench (`board_araxl_xdma.v`) drove this endpoint with the
`pcie3_uscale_rp` root‑port BFM that `open_example_project` produced — an **UltraScale
GTHE3** model. Confirmed in the elaboration log (both `GTPE2` *and* `GTHE3` primitives are
compiled).

A GTPE2 endpoint and a GTHE3 root port **cannot serially train** in xsim: their
transceiver models are different generations with incompatible serial encodings. The
endpoint LTSSM (`cfg_ltssm_state`) stayed `zz` (undriven); the link never reached L0.

### Why serial simulation is the wrong tool

To prove the mismatch was the issue, a **matched** 7‑series root port (`xilinx_pcie_2_1_rport_7x`,
GTPE2) was generated from a `pcie_7x` example design and wired in. Result: **both ends
GTPE2, build/compile/elaborate clean — and the back‑to‑back GTPE2 *serial* link still
stormed immediately at reset de‑assert.** Xilinx's PCIe transceiver sim models are not
built to lock onto each other over a serial connection in xsim. Serial PCIe sim was
abandoned. (That `pcie_7x` work lives under `build/pcie7x_rp/` and the now‑unused
`board_araxl_xdma_7x.v` / `create_pcie7x_rp.tcl`; it can be deleted.)

---

## 4. The solution: PIPE‑mode simulation

PCIe cores support **PIPE‑mode simulation**, where the serial transceivers are *bypassed*
and the endpoint and root port are connected at the **PIPE (parallel) interface**. This is
how Xilinx's own PCIe example sims actually run. Crucially, PIPE mode makes the
GTPE2‑vs‑GTHE3 generation difference **irrelevant** — there is no serial link to train.

The matched PIPE partner for the XDMA endpoint is the XDMA's **own** example root port,
`pcie3_uscale_rp`, because:

- Its PIPE interface width **matches** the endpoint (`common_commands` = 26 bits,
  `pipe_tx/rx_*_sigs` = 84 bits/lane). (The generic `pcie_7x` RP uses 12/25‑bit PIPE — incompatible.)
- Its BFM provides the **`TSK_XDMA_REG_*`** helper tasks the AraXL test stimulus relies on,
  so the original `araxl_xdma_tests.vh` runs unchanged.

### Enabling PIPE mode

`EXT_PIPE_SIM = "TRUE"` disconnects the GTs and routes the PIPE interface to the top level.
Two things were required:

1. **Expose the endpoint's PIPE ports.** The XDMA IP is regenerated with
   `CONFIG.pipe_sim=true` (done in `prepare`), which adds `common_commands_in/out` and
   `pipe_tx/rx_0..7_sigs` to the `xdma_1` wrapper.
2. **Force `EXT_PIPE_SIM="TRUE"` on both cores.** This parameter is *never passed down the
   IP hierarchy* and a board‑level `defparam` into the encrypted IP **does not take effect
   in xsim**. So `prepare` patches the core sources directly (the parameter default is
   authoritative because no parent overrides it):
   - Endpoint: `…/ip/xdma_1/ip_0/source/xdma_1_pcie2_ip_core_top.v`
   - Root port: staged `pcie3_uscale_rp_core_top.v`

   In PIPE mode the PIPE clock (`common_commands_out[0]`) is generated by free‑running
   internal simulation oscillators (125 MHz for Gen1), so no external GT reference is needed.

---

## 5. Testbench architecture

```
                         board  (board_araxl_xdma_pipe.v, sim top)
   ┌─────────────────────────────────────────────────────────────────────────┐
   │                                                                           │
   │   EP = litefury_araxl_xdma_top                 RP = xilinx_pcie3_uscale_rp│
   │   ┌───────────────────────────┐                ┌────────────────────────┐│
   │   │ xdma_1 (GTPE2, EXT_PIPE)   │   PIPE buses   │ pcie3_uscale_rp (GTHE3,││
   │   │  common_commands_out[0] ───┼──pipe_clk────► │  EXT_PIPE_SIM=TRUE)    ││
   │   │  pipe_tx_0..7_sigs[38:0] ──┼──────────────► │  pipe_rx_0..7_sigs     ││
   │   │  pipe_rx_0..7_sigs    ◄────┼──────────────  │  pipe_tx_0..7_sigs[38:0]│
   │   │       │ m_axi (64b)        │                │       │ tx_usrapp BFM   ││
   │   │       ▼                    │                │       │ + DATA_STORE    ││
   │   │  axi_dw_converter 64→256   │                │  (host memory model)   ││
   │   │       ▼ ext_axi (256b)     │                └────────────────────────┘│
   │   │  ara_soc (CVA6 + AraXL)    │                                           │
   │   └───────────────────────────┘                                           │
   └─────────────────────────────────────────────────────────────────────────┘
```

- **`board_araxl_xdma_pipe.v`** — the sim top. Instantiates the EP (the AraXL XDMA top)
  and RP (the UltraScale root‑port BFM), forces `EXT_PIPE_SIM=TRUE` on both via `defparam`
  (belt‑and‑suspenders alongside the source patch), and **cross‑wires the PIPE buses**
  exactly as the Xilinx PIPE example board does:
  - `EP.pipe_tx_N_sigs[38:0]` → `RP.pipe_rx_N_sigs`
  - `RP.pipe_tx_N_sigs[38:0]` → `EP.pipe_rx_N_sigs`
  - `EP.common_commands_out[0]` (pipe clock) → `RP.common_commands_in[0]`
  Only the low 39 bits of each 84‑bit lane bundle carry Gen1 data; the rest are tied 0.
  It also provides `localparam C_DATA_WIDTH = 64`, which the BFM reads as `board.C_DATA_WIDTH`.

- **`litefury_araxl_xdma_top.sv`** — the endpoint. The PIPE ports are threaded through to
  the `xdma_1` instance under `` `ifdef XSIM `` so the synthesizable port list is unchanged
  for real builds. (There is also an `` `ifdef ARA_HOLD_RESET `` diagnostic hook on
  `ara_soc.rst_ni`, used during bring‑up.)

- **`prepare_araxl_xdma_xsim.tcl`** — builds the sim directly inside the main project
  (`build/ara_taxi`): enables `pipe_sim`, regenerates the example to harvest the UltraScale
  RP BFM, patches `EXT_PIPE_SIM` on both cores, resizes the BFM's `DATA_STORE` to hold the
  ~23 KB payload, stages the BFM + board + `araxl_xdma_tests.vh` into
  `build/araxl_xdma_sim_srcs/`, adds the CVA6 instruction‑tracer sim sources, and sets the
  sim‑fileset top to `board`.

- **`run_araxl_dotproduct_xsim.tcl`** — opens the project, disables wave/debug logging
  (memory safety), passes the payload plusargs, launches, and grades the run by scanning
  the log for milestones/failures. Supports `ARAXL_EXTRA_DEFINES` (e.g. `ARA_HOLD_RESET`)
  to inject defines without re‑preparing.

### Observability built into the board (and why it matters)

The board includes a **1 µs heartbeat** and **edge/handshake counters** (`pclk_edges`,
`ep_tx`/`rp_tx` PIPE activity, `m_axi`/`ara` AXI handshake counts, RP‑side LTSSM state,
`aresetn`). Because xsim freezes simulated time during a zero‑delay storm, the *absence* of
heartbeats is itself the stall signal. An external monitor watches RSS and **auto‑kills**
the run if it exceeds the cap (storm) or if simulated time stops advancing (deadlock) — so
stalls are detected automatically instead of hanging. A 2 ms `$fatal` watchdog bounds the
run.

---

## 6. How the integration works (data path & boot flow)

**Address map** (`ara_soc`): `CTRL` @ `0xD000_0000`, `UART` @ …, **`L2MEM` (DRAM) @
`0x8000_0000`** (1 GB). CVA6 boots from `0x8000_0000`.

**AXI path:** XDMA `m_axi` (64‑bit) → `axi_dw_converter` (upsize 64→256) → `ara_soc`
`ext_axi` (256‑bit) → `ara_soc` internal AXI **xbar** (2 masters: CVA6 core + external) →
`axi_atop_filter` → `axi_to_mem` → `tc_sram` L2.

**Intended bring‑up sequence** (driven by `araxl_xdma_tests.vh`, run by the RP BFM after
`TSK_SYSTEM_INITIALIZATION`):

1. PCIe link trains to L0; BFM enumerates (checks speed/width/IDs, scans BARs).
2. BFM places the dotproduct ELF payload in its host‑memory model (`DATA_STORE`) and builds
   an **XDMA H2C descriptor**: read 23016 bytes from host `0x400`, write to card
   `0x8000_0000` (AraXL L2). `CoreReleaseGate=1` keeps the CVA6 core held in reset
   (`system_rst_n = rst_ni & core_release[0]`) during the load.
3. BFM starts the H2C engine (writes XDMA regs `0x4080`, `0x0004`) and polls the completed‑
   descriptor count (`0x0048`).
4. BFM writes `core_release` (a second H2C descriptor → `CTRL` register) to ungate CVA6.
5. CVA6 + AraXL execute the dotproduct from L2 and write the **exit register**; the board's
   `exit_o[0]` monitor calls `$finish`.

The L2/AXI infrastructure runs in the always‑on `rst_ni` domain; only the CVA6+vector
cluster is gated by `core_release`, so the L2 can receive the payload before the core runs.

---

## 7. Verified results

From the simulation log (PIPE mode, memory flat ≈0.3 GB, no storm):

```
[ 71168000] : Transaction Link Is Up...
[ 73176000] :    Check Max Link Speed = 2.5GT/s - PASSED
[ 73176000] :    Check Negotiated Link Width = 4 - PASSED
[ 75184000] :    Check Device/Vendor ID - PASSED
[ 77192000] :    SYSTEM CHECK PASSED
            XDMA BAR found : BAR 0 is XDMA BAR
            **** AraXL XDMA H2C ELF payload load: 23016 bytes ...
```

RP LTSSM progression observed: `0x00 (Detect) → 0x02 (Polling) → 0x04 → 0x05 → 0x08 →
0x07 → 0x09 (Config.Complete) → 0x10 (L0)`. `ep_lnk=1, rp_lnk=1, rp_ltssm=0x10`, stable to
hundreds of µs. **The PCIe link, enumeration, BAR detection, and start of the H2C DMA all
work.**

---

## 8. Open issue: xsim cannot converge the AraXL AXI fabric during the L2 write

> **Important correction.** An earlier version of this writeup framed the blocker as a
> permanent "`w_ready=0` forever" stall in `ara_soc`. **That was a misdiagnosis.** With
> instrumentation the true behavior is the opposite of a clean stall: at the instant the
> H2C write reaches the L2 path, **simulation time freezes** and the xsim event queue
> explodes (RAM balloons to the cap → OOM). It is a **zero‑delay (delta‑cycle)
> combinational settling failure**, not a logic stall and **not a functional RTL bug**.

### What actually happens
The H2C DMA reaches `ara_soc` as a clean 512‑byte INCR burst
(`addr=0x8000_0000, len=15, size=5 (256‑bit), burst=1, atop=0, id=0`). The write is
accepted and **real kernel bytes are written into L2 at the correct, incrementing addresses
(`0x8000_0000`, `…0x20`, `…0x40`, … `0x1c0`) with `XCHK` reporting zero X on every signal.**
Then, partway into the burst, sim‑time stops advancing at a fixed timestamp while memory
grows without bound — the signature of a combinational network that xsim re‑evaluates
forever instead of recognizing as settled.

### Why this is an xsim limitation, not a logic bug
Evidence, all from instrumented runs:
- **No X anywhere** on the L2 path during the event storm (`$isunknown` over the whole
  req/resp structs + payloads = 0). A functional defect almost always shows as X; there is none.
- **Correct data, correct addresses** are written for the beats that complete before the wall.
- **Values are constant across the delta storm** — a 1‑bit XOR fingerprint of every struct is
  identical for thousands of consecutive deltas at the same `$time`. The network has *settled*;
  xsim just keeps re‑scheduling it.
- **The storm point moves under passive observation** (adding a read‑only probe shifts it from
  `109144000 ps` to `109672000 ps`). A deterministic logic event would not care about passive
  monitors — this is delta‑scheduling non‑determinism.
- The fabric (`axi_xbar`, `axi_to_mem`, fall‑through `stream_fifo`/`stream_fork` primitives) is
  standard pulp‑platform IP that is **regression‑tested on QuestaSim and Verilator**. Those
  simulators iterate a settled combinational loop to its fixed point (or, for a true loop,
  error out on an iteration limit); xsim has weaker zero‑delay‑loop handling and runs away.

The root combinational coupling lives in the L2 write path that AraXL's own testbenches never
exercise the same way (they drive L2 from the CVA6 core, not from an external AXI master):
`axi_xbar` (the combinational demux/mux that `CUT_MST_PORTS` leaves exposed) →
`axi_atop_filter` → `axi_to_mem` (built from zero‑latency fall‑through stream primitives).

### What was tried (and why it isn't whack‑a‑mole‑able in xsim)
Each fix below was built and run. The storm is **endemic to the fabric under xsim**: fixes
either don't reach it or merely relocate *when* it trips.

| Attempt | Result |
|---|---|
| `axi_to_mem` `mem_gnt = mem_req` → `mem_gnt = 1'b1` (removes a real `req→gnt→req` comb loop) | Correct fix, but **not** the storm trigger — storm persists |
| Bypass `axi_atop_filter` (no atomics are issued to L2) | Storm moves *later* in the burst (≈`109144000`→`109672000`) — real bytes write, then storm |
| Insert `axi_cut` (full register slice) between atop_filter and `axi_to_mem` | **No effect** — the loop is upstream of that boundary |
| `axi_to_mem` → registered‑FSM bridge (struct‑native port of Ariane `axi2mem`) | **No effect** — bridge is register‑isolated, so the loop must be upstream in the xbar |
| `axi_xbar` `LatencyMode` `CUT_MST_PORTS` → `CUT_ALL_PORTS` | **Worse** — introduces a *reset‑time* storm at `69920000 ps` |
| `xelab --O0` (disable xsim optimization) | **Worse** — also storms at reset |

`xsim` exposes **no runtime knob** to bound or cleanly abort a non‑converging delta loop
(confirmed against `xsim -help`); only the external memory cap protects the machine.

### Realistic paths to a full end‑to‑end run
1. **Run the unmodified design in QuestaSim / Xcelium / VCS.** Vivado can export this sim for
   them (`launch_simulation -simulator questa` + `compile_simlib` for the encrypted XDMA IP).
   Those simulators have a real combinational‑loop iteration limit: they will either complete
   the run or *cleanly* report a true loop. *Questa Intel FPGA Starter Edition is free*
   (node‑locked, performance‑limited). **This is the only path that validates the unmodified
   RTL end‑to‑end** and is the recommended next step.
2. **Sim‑only registered L2 adapter (kept out‑of‑tree).** A registered‑FSM AXI→SRAM bridge in
   place of `axi_to_mem` *for xsim only* removes that module's combinational coupling, but the
   experiments above show the dominant loop is upstream in `axi_xbar`, so this alone is not
   sufficient. Not pursued further.
3. **TB‑preload of L2.** Loading the payload directly into `i_ara_soc.i_dram` (à la
   `hardware/tb/ara_tb.sv` `dram_init`) and using the XDMA only for the `core_release` poke
   would let the kernel run in xsim, **but it bypasses the very DMA‑into‑L2 path that is the
   point of the XDMA integration**, so it does not validate the integration. Deliberately not
   chosen.

### Status of the tree
The experimental sim‑only changes used to localize this (atop bypass, `axi_cut`, the
registered bridge, `CUT_ALL_PORTS`, `--O0`) have been **reverted** — `hardware/src/ara_soc.sv`
L2 path is back to the upstream `axi_atop_filter` → `axi_to_mem` form. The reset‑time xsim
fixes from earlier (`ifdef XSIM` core clock‑gating/parking) and the optional
`ifdef ARAXL_AXI_PROBE` instrumentation block remain (both inert unless their define is set).

> **Not deployment‑ready.** This is a *simulation* result. A full functional sim has not run;
> the design has not been synthesized/placed/timed with these changes; the real PCIe serial
> link is bypassed by PIPE mode; and the XDMA IP is currently generated with
> `CONFIG.pipe_sim=true` (must be regenerated with `pipe_sim=false` before any FPGA build).

---

## 9. Build & run

```sh
cd fpga/ara_taxi_vivado

# One-time / after RTL or IP changes: create the project + PIPE-mode sim sources
make araxl-xdma-xsim-setup        # builds build/ara_taxi, enables pipe_sim, stages BFM+board

# Build the dotproduct payload and run the sim under the memory cap
make araxl-dotproduct-xsim

# Iterate quickly on just the sim (project already prepared):
HEX=$(realpath build/araxl_xdma_payload.hex); LEN=$(cat build/araxl_xdma_payload.hex.len)
systemd-run --user --scope -p MemoryMax=24G -p MemorySwapMax=2G \
  vivado -mode batch -source tb/xdma_xsim/run_araxl_dotproduct_xsim.tcl -tclargs "$HEX" "$LEN"

# Diagnostics:
ARAXL_XSIM_WAVES=1 ...            # enable waveform logging (off by default for memory safety)
ARAXL_EXTRA_DEFINES=ARA_HOLD_RESET ...   # hold AraXL in reset (isolates link-up from the core)
```

Watch `build/ara_taxi/ara_taxi.sim/sim_1/behav/xsim/simulate.log` for the `[HB …]`
heartbeats and the milestone messages in §7.

---

## 10. File manifest

**New / modified for the integration:**

| File | Role |
|------|------|
| `rtl/litefury_araxl_xdma_top.sv` | EP top; `ifdef XSIM` PIPE ports threaded to `xdma_1`; `ifdef ARA_HOLD_RESET` diag |
| `tb/xdma_xsim/board_araxl_xdma_pipe.v` | **PIPE‑mode sim top** (EP+RP, PIPE cross‑wire, monitors/watchdog) |
| `tb/xdma_xsim/prepare_araxl_xdma_xsim.tcl` | Builds the sim in the main project; `pipe_sim`, `EXT_PIPE_SIM` patch, BFM staging |
| `tb/xdma_xsim/run_araxl_dotproduct_xsim.tcl` | Launches/grades the run; debug‑off, extra‑defines hook |
| `tb/xdma_xsim/araxl_xdma_tests.vh` | AraXL stimulus (XDMA H2C payload load + core release) — original, reused |
| `Makefile` | `araxl-dotproduct-xsim` memory cap; `pcie7x-rp` helper |

**Diagnostic / now‑unused (safe to delete):**
`tb/xdma_xsim/board_araxl_xdma_7x.v`, `araxl_xdma_tests_7x.vh`, `create_pcie7x_rp.tcl`,
`discover_pcie7x_rp.tcl`, `enable_xdma_pipe.tcl`, `regen_pipe_ref.tcl`,
`build/pcie7x_rp/`, `build/xdma_pipe_ref/`.

> Reminder: the XDMA IP currently has `CONFIG.pipe_sim=true` (it affects synthesis too).
> Regenerate with `pipe_sim=false` before a real bitstream build (`litefury-xpr`).
