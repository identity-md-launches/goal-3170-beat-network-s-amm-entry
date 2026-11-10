# Beat qt1 on the Paradigm AMM puzzle

Credit: Taylor (gtmcknight) authored the solved policy, replica, tables, and setup script used here. The qt1 baseline combines Taylor's Gaussian filter and qm tables with qm-spline compression.

Goal: beat IMD's qt1 entry on https://paradigm.xyz/puzzles/amm, board score **524.9403** (8th; 7th 525.377, 6th 526.777). Replica scores are not board scores.

Limits: deployed runtime <= **24,576 bytes**; engine `afterSwap` peak <= **245,000 gas**; **0 OutOfGas**.

## Gates

- **P:** Taylor's `gates.py` reproduces before any change.
- **Q:** score every new Python reference paired against qt1's Python reference on Taylor's replica. Choose on seeds **60000..61023**; report on **10000..12047**.
- **F:** contract fees equal its Python reference within **0.01 bps** on **50 replica runs x 2,000 callbacks**. The reserved Gate F window is 70000..70099.

## Seeds

| Kind | Seeds | Status / purpose |
| --- | --- | --- |
| Engine | 9800000..9801089 | Spent or reserved (includes 9801088..9801089 tools smoke) |
| Engine | 9801090..9802113 | TC-A confirmation block A (e4-confirm-*) |
| Engine | 9802114..9803137 | TC-A confirmation block B (e4-confirm-*) |
| Engine | 9803138..9803185 | e4-combo-port (3 x 16) |
| Engine | 9803186..9803187 | e4-trunk-candidate smoke (Candidate vs qt1, spent) |
| Engine | 9803188..9803571 | Reserved outside the e6-freeze-combo item |
| Engine | 9803572..9804595 | Combo (ComboG(1)) fresh confirmation block A (pending) |
| Engine | 9804596..9805619 | Combo (ComboG(1)) fresh confirmation block B (pending) |
| Engine | 9805620..9805635 | TC-A gap run (pending) |
| Engine | 9805636 | **NEXT FREE ENGINE SEED** |
| Replica | 60000..61023 | Choose |
| Replica | 10000..12047 | Report |
| Replica | 70000..70099 | Gate F |

Engine evaluations use each strategy alone against the 30 bps VanillaStrategy, `amm_sim_rs.run_batch(X, VanillaStrategy, configs, 8)`, with configs built as in `MatchRunner._build_configs`. Use fresh engine seeds, never reuse them; report paired `{n, mean_diff, se, worst5}` against qt1 and `amm_sim_rs.gas_stats()`. Keep state under `scratch/` and individual commands under eight minutes.

## Pinned inputs

- Taylor source: https://github.com/gtmcknight/amm-sim/tree/4812a6382311624e1506aca131ca35c378f930d9/research/solved. Selected files are preserved verbatim in `reference/taylor/`.
- qt1 report, preserved verbatim as `reference/qt1/REPORT.md`: https://api.imd.fun/artifacts/8a6e303b662e1a5ea9bb47f31acedd3988ef65b3ddb66d074517aa59ad41ca40. Its fenced Solidity and Python blocks are `Strategy.sol` and `qmref.py`.
- Blob source: https://api.imd.fun/artifacts/17d249ab0c33fc44931d9b105cf3f9e3846a560bd518b67310c2a56defacdecc. `blob.b64` preserves the Data block; `blob.bin` is its decoded content.
- `Strategy.sol` SHA256: `c68887cff61180e12ba2b1ceb333edf76a830f91f63b5d775a8806fb9ec08aca`.
- `blob.bin` SHA256: `3ac7cb8811ecfb6a17f499aa4e9b70dd55f7fb6432b3aec3b904e11a3dece38e`.

The 7,892,018-byte `qm_k1e-5.json` is deliberately not vendored. Download it from https://raw.githubusercontent.com/gtmcknight/amm-sim/4812a6382311624e1506aca131ca35c378f930d9/research/solved/qm_k1e-5.json and verify SHA256 `5ff53e42ca87390e5f65d1caa3f7a480e67a8212fb0670274dfd562b05ba1afd`.

For replica checks, copy `reference/taylor/` into a scratch directory and place the downloaded qm table beside `gates.py`; run `python3 -I gates.py` there. Copy `reference/qt1/qmref.py` and `blob.bin` alongside the replica to check `replica2.run(10000, QMRef('blob.bin'))['edge']` (expected 443.101741). With `-I`, a small driver must explicitly insert its own directory in `sys.path`, as Taylor's scripts do.

See `tools/README.md` for the pinned engine setup. This tools item preserves the baseline and consumes the assigned engine smoke seeds 9801088..9801089.


## Candidate

- `contracts/Candidate.sol` (TC-A, `TaylorTwoCompQmTrim2`): `reference/qtr2/Strategy.sol` + `contracts/candidate.diff` (`patch -p1`), SHA256 `b87234c89e094f4955578417c1266129b0f96e6dfda68e3fb8866e00eeda71a2`, deployed runtime **21,102 bytes** (solc 0.8.24, challenge compiler).
- Python reference: `reference/twocomp/twocomp.py`, `TwoComp`, `DUAL_CUTS=2`.
- Gates: [reference/candidate/GATES.md](reference/candidate/GATES.md) (P, Q +0.4248 ± 0.0122 vs qt1-ref on 10000..12047, gas probe 177,611, F max 6.3e-6 bps on 50 x 2,000, engine +0.4145 ± 0.0423 vs qt1 on n=128, peak 201,916, 0 OOG).
- COMBO references (replica only): [reference/combo/README.md](reference/combo/README.md).

TC-A is the **confirmed fallback**: it is the candidate to use unless Combo passes its fresh confirmation.

## Combo (ComboG(1), frozen, NOT yet confirmed)

Credit: Taylor (gtmcknight) for the replica, Gaussian filter, fee rule and qm tables that ComboG builds on.

- `contracts/Combo.sol` (`TaylorComboGQmTrim2`) = `contracts/Candidate.sol` (TC-A) + `contracts/combo.diff` (`patch -p1` or `git apply -p1` against a copy named `Candidate.sol`). SHA256 `f904a486b1dcfbd6fcf40aa48920d1bb6b79ad2ac1c99a2cbbb16d4272c2c616`, 47,171 bytes. `combo.diff` SHA256 `ee1e263770b2beecda27dbf2b85365c6536dd1e6f4c69f3ed5ad6451d39290b2`. Both come verbatim from the [gd-ab-1 report](https://api.imd.fun/artifacts/9b842d35c17245af4dd2bfc0ec608263f9b7edcb2db619cffba7d36d1d853740).
- Python reference: `reference/combo/combog.py`, `combog.ComboG`, `GATE = 1`, SHA256 `321c61dff43c1677722d4b52e066ed5296f08ac7b72465245f04eb04e1c143cb`, 6,011 bytes. It imports `twocomp` (unchanged, `DUAL_CUTS=2`, SHA256 `9d3c1833…f0f0af`) and reads `reference/qt1/blob.bin` (`3ac7cb88…e38e`). Standard library only.
- Evidence, all reported by gd-ab-1 and not re-run here: [reference/combo/GATES.md](reference/combo/GATES.md) (Q vs qt1-ref +0.6029 ± 0.0130 on 10000..12047; F max 3.1e-6 bps on 50 x 2,000; dt=1 probe peak 203,136; runtime 22,058 bytes; 0 OOG on the sampled replays, no universal gas bound). Its engine run on 9800000..9800007 reused seeds and is excluded.
- **Final confirmation is pending** (fresh engine seeds A 9803572..9804595, B 9804596..9805619; TC-A gap 9805620..9805635; next free 9805636). No board score is claimed. The requester decides on and makes any board submission.

Prerequisites: replica checks need only `python3` (stdlib). Compile, F and engine need the pinned challenge setup in [tools/README.md](tools/README.md) (Linux x86_64, `uv`, solc 0.8.24, `amm_sim_rs` wheel, `pyrevm==0.3.7`).

Rebuild and replica replay, from the repository root:

```sh
mkdir -p test/scratch/rebuild && cp contracts/Candidate.sol test/scratch/rebuild/
(cd test/scratch/rebuild && patch -p1 < ../../../contracts/combo.diff)  # or: git apply -p1
sha256sum test/scratch/rebuild/Candidate.sol contracts/Combo.sol   # both f904a486...
python3 -I -c "import sys,os;R=os.getcwd();sys.path[:0]=[R+'/reference/combo',R+'/reference/taylor']
import replica2;from combog import ComboG
print(replica2.run(10000,ComboG(R+'/reference/qt1/blob.bin'))['edge'])"   # 444.3066107552986
```

Startup imports: `reference/combo` (for `combog` and `twocomp`) and `reference/taylor` (for `replica2`) must be on `sys.path`; with `-I`, insert them explicitly as above.

Compile, F and engine, from the engine checkout after the tools setup (`TASK_ROOT` = repository root). `tools/check.py` does not put `reference/combo` on its path, so add it with `PYTHONPATH` (its `reference/twocomp/twocomp.py` is byte-identical to `reference/combo/twocomp.py`):

```sh
. scratch/env.sh && timeout 470 amm-match validate "$TASK_ROOT/contracts/Combo.sol"
. scratch/env.sh && PYTHONPATH="$TASK_ROOT/reference/combo" timeout 470 python "$TASK_ROOT/tools/check.py" \
  "$TASK_ROOT/contracts/Combo.sol" combog.ComboG 70000 70050 scratch/F_combo_70000_70050.json
. scratch/env.sh && timeout 470 python "$TASK_ROOT/tools/engine.py" \
  "$TASK_ROOT/contracts/Combo.sol" "$TASK_ROOT/reference/qt1/Strategy.sol" START END scratch/engine_combo_START_END.json
```

Run engine ranges only from the fresh blocks above, in chunks short enough for eight minutes, and never repeat a seed.

## Where things are

- `reference/qt1/`: unchanged baseline Solidity, Python reference and decoded table blob.
- `reference/taylor/`: unchanged pinned replica and Taylor gate inputs.
- `reference/qtr2/`: verified gas-trimmed Solidity, verbatim span-search patch and patched Solidity.
- `reference/twocomp/` and `reference/mix/`: verbatim two-component and posterior-mixture Python references.
- `contracts/`: frozen candidate TC-A and its diff, plus unconfirmed `Combo.sol` and `combo.diff` (against TC-A); `reference/candidate/`: TC-A gate record; `reference/combo/`: COMBO references, `combog.py` and the ComboG `GATES.md`.
- [reference/CHECKS.md](reference/CHECKS.md): three-seed replica values, provenance and reproduction commands.
- [tools/README.md](tools/README.md): engine setup and CLI commands for `check.py` (effective-fee Gate F replay) and `engine.py` (paired engine comparisons).
