# CTM + AES-128 Accelerator Subsystem — Software Interface

This document describes the memory-mapped register interface exposed by
`accelerator_subsystem_ctm.v` / `soclabs_ahb_ctm_ctrl.sv`, for software
(bare-metal C) driving the accelerator over AHB-Lite.

The subsystem exposes **4 memory regions** on one AHB bus:

| Region | Base address | Purpose |
|---|---|---|
| 0 — Control/ID | `0x0000` | Chip ID, model config, status |
| 1 — Image | `0x1000` | Load one image chunk at a time into the Tsetlin Machine |
| 2 — Clause | `0x2000` | Program the TM's clause memory |
| 3 — Weight | `0x3000` | Program the TM's weight memory |
| 4 — AES-128 | `0x4000` | Standalone AES-128 encrypt/decrypt |

All addresses below are **offsets from the subsystem's base address**
(`ACCEL_BASE` in the C code) — substitute your actual system's base address
for the accelerator in your platform's memory map / linker script.

---

## Region 0 — Control / ID (0x0000–0x0020)

| Offset | Name | Access | Description |
|---|---|---|---|
| `0x0000` | CORE_NAME0 | R | ASCII `"ctm "` (0x63746d20) |
| `0x0004` | CORE_NAME1 | R | ASCII `"top "` (0x746f7020) |
| `0x0008` | CORE_VERSION | R | ASCII `"0.01"` (0x302e3031) |
| `0x0010` | CTRL | R/W | `[1:0]` = resetessen (reset-cause bits into class_top) |
| `0x0014` | MODEL_PARAMS | R/W | `[2:0]`=patch_size, `[5:3]`=stride, `[13:6]`=clause count, `[17:14]`=class count |
| `0x0018` | X_W | R/W | `[6:0]` chunk-load index counter |
| `0x001C` | STATUS | R | `[0]`=tready (classification done), `[7:4]`=output_params (predicted class 0–9) |
| `0x0020` | LOAD_STATUS | R | `[7:0]`=bram_addr_a, `[15:8]`=bram_addr_a2 — **poll these while loading clause/weight data** |

**Important — no backpressure on load:** `class_top` has no ready/stall
signal for clause/weight loading. It free-runs and consumes one new
clause/weight word per clock while `bram_addr_a`/`bram_addr_a2` are below
the configured clause/weight count. Software must poll `LOAD_STATUS` to
know when loading is progressing/complete — writing faster than the core
consumes, or stopping early, will misalign the load.

---

## Region 1 — Image (0x1000)

| Offset | Name | Access | Description |
|---|---|---|---|
| `0x1000` | TDATA | W | 32-bit image chunk. Re-sampled by the core every cycle it's not stalled — write once per chunk in sequence with `X_W`. |

---

## Region 2 — Clause (0x2000–0x201F)

256-bit clause word, written as **8 sequential 32-bit writes to the same
address region**.

**Word ordering (important, non-obvious):** the underlying packet
constructor places the **last word written into the MSBs** and the
**first word written into the LSBs** — the opposite of a naive top-down
reading of the address range. See the worked example in the C code.

| Offset | Access |
|---|---|
| `0x2000`–`0x201C` | W (8 sequential 32-bit writes, any offset in range works — the packet assembles based on write order, not the specific address) |

---

## Region 3 — Weight (0x3000–0x301F)

Same 256-bit / 8-word packet convention as Region 2 (clause).

---

## Region 4 — AES-128 (0x4000–0x404F)

| Offset | Name | Access | Description |
|---|---|---|---|
| `0x4000`–`0x401C` | AES_KEY | W | 256-bit key, 8×32-bit writes, same **last-write-is-MSB** ordering as clause/weight. For AES-128, only the upper 128 bits (`key[255:128]`) are used — see worked example. |
| `0x4020`–`0x402C` | AES_BLOCK | W | 128-bit plaintext/ciphertext input, 4×32-bit writes, same last-write-is-MSB ordering. |
| `0x4030` | AES_CTRL | R/W | `[0]`=init (pulse — triggers key expansion), `[1]`=next (pulse — triggers block encrypt/decrypt), `[2]`=encdec (1=encrypt, 0=decrypt), `[3]`=keylen (0=AES-128, 1=AES-256) |
| `0x4034` | AES_STATUS | R | `[0]`=ready (key expansion done, core idle), `[1]`=result_valid (block operation complete) |
| `0x4040`–`0x404C` | AES_RESULT | R | 128-bit result, 4×32-bit reads, **MSW-first** (conventional ordering — this is a hand-built read mux, NOT subject to the write-side packet-constructor reversal above). |

**AES operation sequence:**
1. Write KEY (8 words, last word written = MSBs, i.e. `key[255:224]`).
2. Write BLOCK (4 words, last word written = MSBs, i.e. `block[127:96]`).
3. Write AES_CTRL with `encdec`/`keylen` set and `init=1` to start key expansion.
4. Poll AES_STATUS until `ready=1`.
5. Write AES_CTRL with `next=1` (keep `encdec`/`keylen` the same) to start the block operation.
6. Poll AES_STATUS until `result_valid=1`.
7. Read AES_RESULT (4 words, MSW-first at `0x4040`).

AES-128 and the Tsetlin Machine are **functionally independent** —
nothing written to Region 4 affects Regions 1–3, and vice versa. They
share only the bus, not any data path, in this build.

---

## Files

- `soclabs_ahb_ctm_ctrl.sv` — the register/control wrapper (this document describes its interface)
- `accelerator_subsystem_ctm.v` — top-level AHB shell
- `combined_smoke_tb.v` — reference testbench; the C code's sequencing mirrors this file's stimulus exactly
- `accel_driver.c` / `accel_driver.h` — example bare-metal C driver implementing everything in this document
