# Replica and engine harnesses

Credit: Taylor (gtmcknight) for the solved policy, tables, replica and setup. `setup.sh` remains the verbatim pinned Taylor setup-fast script. `check.py` adapts SP's replay.py; `engine.py` adapts SP's engine.py, preserving its direct transcription of MatchRunner's default config construction.

Run the commands below from the goal repository root on Linux x86_64. All caches, outputs, dependencies and the disposable engine checkout live inside `test/scratch/`; runtime state is in that checkout's `scratch/`. No submodule is needed. Setup was executed successfully in this layout.

```sh
TASK_ROOT=$PWD
mkdir -p test/scratch
git clone https://github.com/benedictbrady/amm-challenge test/scratch/amm-challenge
git -C test/scratch/amm-challenge checkout 6b6921f8d463314aa7c96234e1be25a25245f704
mkdir -p test/scratch/amm-challenge/scratch
cp tools/setup.sh test/scratch/amm-challenge/scratch/setup.sh
cd test/scratch/amm-challenge
sh scratch/setup.sh
```

Run subsequent commands from the engine checkout. Each seed range is **start inclusive, end exclusive**. Keep each invocation below eight minutes; `timeout 470` provides a hard limit on Linux. Use small chunks for large ranges. Replica-only input checks in [CHECKS.md](../reference/CHECKS.md) use plain `python3 -I` and require no engine environment.

Gate F example (this assigned smoke seed was executed):

```sh
. scratch/env.sh && timeout 470 python "$TASK_ROOT/tools/check.py" \
  "$TASK_ROOT/reference/qt1/Strategy.sol" qmref.QMRef \
  70000 70001 scratch/F_qt1_70000_70001.json
```

`check.py CONTRACT MODULE.CLASS START END OUTPUT` loads bundled reference modules and blob from the goal repository, creates a fresh pyrevm deployment and fresh reference policy per seed, and drives the replica with the reference's fees. It checks initialization and exactly the first 2,000 own-pool afterSwap callbacks, with 245,000 gas per EVM call. Expected fees are clamped by `replica2.clampf` to `[0, 0.1]`; the tolerance is 0.01 bps. Mismatch, revert, out of gas, malformed output, or insufficient callbacks fails the command. It retains SP's JSON `rows` / `seconds` and per-row `seed`, `n`, `max_error_bps`, `peak`, `sum_gas`, `sha256` maps, with one arm named `candidate`. Gas totals and hashes cover afterSwap only. A successful one-seed smoke is not the full 50 × 2,000 Gate F.

Bundled reference names: `qmref.QMRef`, `twocomp.TwoComp`, `wavg_fees.QMRef`, `wavg_offsets.QMRef`. Each constructor takes the bundled blob path. Initialization receives the replica's actual run configuration.

Engine example (these two assigned seeds were executed; **do not rerun them**):

```sh
. scratch/env.sh && timeout 470 python "$TASK_ROOT/tools/engine.py" \
  "$TASK_ROOT/reference/qt1/Strategy.sol" "$TASK_ROOT/reference/qt1/Strategy.sol" \
  9801088 9801090 scratch/engine_qt1_qt1_9801088_9801090.json
```

`engine.py CANDIDATE BASELINE START END OUTPUT` runs each arm separately against the 30 bps VanillaStrategy, using `amm_sim_rs.run_batch(X, Vanilla, configs, 8)`. Configs match `MatchRunner._build_configs` with default baseline variance. The first contract's edge minus the second's defines the paired difference. JSON contains each arm's per-seed edges, raw `gas_stats()`, source hash and timing, plus `paired {n, mean_diff, se, worst5}`. `se` is the sample standard error, or null for one seed; `worst5` lists the five lowest paired differences with their seeds. Each arm resets gas statistics first.

An engine output is created exclusively before simulation, and updated after each arm so interrupted runs retain their reservation and partial results. This prevents overwriting that output; it cannot detect reuse under a different filename. Consult the repository seed ledger and reserve fresh windows before running. All seeds through **9801089** are spent or reserved; the next free seed is **9801090**. Use the same assigned seeds for the two paired arms only. Compilation caches live in the engine checkout's `scratch/`, keyed by source SHA256. The reported runtime size should be checked against 24,576 bytes, and engine gas against 245,000 with zero OutOfGas.

Optional solver dependencies (not needed for these harnesses):

```sh
. scratch/env.sh && uv pip install numba cma
```

On other platforms, `python3 -m py_compile tools/check.py tools/engine.py` checks syntax only; it does not execute the engine or Gate F. The delivered smoke tests were executed on Linux x86_64.
