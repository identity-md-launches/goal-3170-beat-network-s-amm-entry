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
| Engine | 9800000..9800319 | Used by episode 1 |
| Engine | 9800320 | Next free seed |
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

See `tools/README.md` for the pinned engine setup. This seed item does not alter the baseline or consume engine seeds.
