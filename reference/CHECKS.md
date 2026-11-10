# Replica input checks

Credit: Taylor (gtmcknight), replica, Gaussian filter and qm tables; the two-component and mixture references retain their source credits. Extracted code is verbatim. These three seeds are input checks, not a full Gate Q evaluation or evidence of a board improvement.

Executed with plain `python3 -I`, using `reference/taylor/replica2.py` and the unchanged `reference/qt1/blob.bin` (SHA256 `3ac7cb8811ecfb6a17f499aa4e9b70dd55f7fb6432b3aec3b904e11a3dece38e`). Edges rounded to six decimal places:

| Reference | 10000 | 10001 | 10002 |
| --- | ---: | ---: | ---: |
| `qmref.QMRef` | 443.101741 | 571.454483 | 525.908441 |
| `twocomp.TwoComp` | 443.690614 | 571.968071 | 526.124475 |
| `wavg_fees.QMRef` | 444.116689 | 571.977148 | 525.771328 |
| `wavg_offsets.QMRef` | 444.115542 | 571.986018 | 525.772792 |

The execution driver was `python3 -I test/scratch/replica_checks.py`. The following equivalent standalone command reproduces every value from the goal repository root (explicit paths are necessary under `-I`):

```sh
python3 -I - <<'PY'
import pathlib, sys
root = pathlib.Path.cwd()
for directory in ('reference/taylor', 'reference/qt1', 'reference/twocomp', 'reference/mix'):
    sys.path.insert(0, str(root / directory))
import replica2, qmref, twocomp, wavg_fees, wavg_offsets
for cls in (qmref.QMRef, twocomp.TwoComp, wavg_fees.QMRef, wavg_offsets.QMRef):
    for seed in range(10000, 10003):
        result = replica2.run(seed, cls(str(root / 'reference/qt1/blob.bin')))
        print(cls.__module__ + '.' + cls.__name__, seed, f"{result['edge']:.6f}")
PY
```

## Provenance

- `qtr2/Strategy.sol`: Solidity fence of [R](https://api.imd.fun/artifacts/18ca35cb47390b8e8c289b240d7836804692998ad64f84ef248c43d61e199f0b), 43,073 bytes; asserted SHA256 `7b99afae570ef1627b0163fb21411f14c496b005a07c3966cc7323906dee664f`.
- `qtr2/spans.diff`: diff fence under “Patch and invariants” of [SP](https://api.imd.fun/artifacts/cc5f5917337662ddf10ac494ed6593d06322b46d50fb475b99108cb9f3f15686). Applied using `patch reference/qtr2/StrategySpans.sol reference/qtr2/spans.diff` to a copy of `Strategy.sol`; asserted resulting SHA256 `bbf63364ed407fc3a94ec3b4cc02223b6855b1b9c083e6e7a7566a2ba70e24b5`.
- `twocomp/twocomp.py`: Python fence under Code in [two-component source](https://api.imd.fun/artifacts/d3c849db2ac31e567b57e52b80b86e8c24c842e5b4125b9d75c78e3cb07115b9).
- `mix/wavg_fees.py`: Python fence under Code in [fee mixture source](https://api.imd.fun/artifacts/23cf289cf15eff6790cb2067a714df9d020049d2de5f3975c11857ab344cb9e4).
- `mix/wavg_offsets.py`: Python fence under Code in [offset mixture source](https://api.imd.fun/artifacts/6b911ad2ead493aa3d39cd55d4e95fc41ca09b4024e366655cd238825b37c6c4).

Fence content includes its final newline; no credits or formatting were added to these verbatim inputs. Harnesses are adaptations of SP's Scripts section, with paths and CLI generalized.

## Original Taylor gates

Also ran `timeout 470 python3 -I gates.py` in `test/scratch/gates/`, with copies of the unchanged Taylor scripts and `pol_mid.json`, plus the pinned `qm_k1e-5.json` (SHA256 `5ff53e42ca87390e5f65d1caa3f7a480e67a8212fb0670274dfd562b05ba1afd`). All columns reproduce the baseline report:

```text
seed   perfect-info      gaussian+plain    gaussian+qm       lattice+qm
10000  448.261189  443.455598  443.522608  443.663520
10001  576.779199  571.463409  571.623551  571.977293
10002  531.886497  525.168028  525.865859  526.411631
```

These checks were run after importing the immutable source inputs; no policy changes were made.

## Linux harness smoke results

Exact CLI reproduction is in [tools/README.md](../tools/README.md). Setup and both smoke tests executed successfully on the pinned checkout; no command exceeded eight minutes.

- Gate F smoke: qt1 / `qmref.QMRef`, seed 70000, 2,000 callbacks; maximum effective-fee error **0.000001504893 bps**, pyrevm afterSwap peak **177,686 gas**, total **253,658,209 gas**. Callback ABI-output SHA256 `221472443e11ab733f0f2f33f8a59c135909b690af1b9ee93aad0af702e2a782`.
- Engine smoke: qt1 versus qt1, each alone versus Vanilla, seeds 9801088 and 9801089. Edges for both arms: **573.595237186163**, **591.10427219484**. Paired `n=2`, `mean_diff=0`, `se=0`; both worst differences zero. Submission afterSwap peak **200,361 gas**, **23,027** successful callbacks per arm, **0** OutOfGas, reverts, other halts, transaction errors or bad returns across all callbacks. Compiled qt1 runtime **20,605 bytes**.
- Additional checks: syntax for both harnesses and all three imported Python inputs; verbatim fence equality; exact span hash; config parity against `MatchRunner._build_configs` on five seeds and twelve fields; known nonzero paired statistics and the one-seed standard-error case; successful smoke JSON invariants. These config-only checks ran no engine simulations or additional engine seeds.

No command or check failed. Full 50-seed Gate F, full choose/report Gate Q, and engine evaluations of the imported candidate contracts were not run in this bounded tools item. The smoke tests validate harness operation, not candidate performance.
