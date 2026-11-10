# ComboG(1) gate record (frozen handoff, confirmation pending)

Credit: Taylor (gtmcknight) authored the replica (`replica2.py`), Gaussian filter, fee rule, qm tables and `gates.py` ([amm-sim @4812a638, research/solved](https://github.com/gtmcknight/amm-sim/tree/4812a6382311624e1506aca131ca35c378f930d9/research/solved)). ComboG builds on that work through IdentityMD's TwoComp, COMBO and qt1-reference items.

**Source of every figure below:** the gd-ab-1 report, artifact D = <https://api.imd.fun/artifacts/9b842d35c17245af4dd2bfc0ec608263f9b7edcb2db619cffba7d36d1d853740>. They are D's measurements, attributed to D, and were **not** re-run by the freeze item except where marked "re-checked here". No board score is claimed.

## Frozen artifacts

| File | Bytes | SHA-256 | Origin |
| --- | ---: | --- | --- |
| `contracts/Combo.sol` (`TaylorComboGQmTrim2`) | 47,171 | `f904a486b1dcfbd6fcf40aa48920d1bb6b79ad2ac1c99a2cbbb16d4272c2c616` | `contracts/Candidate.sol` (TC-A) + `contracts/combo.diff` |
| `contracts/combo.diff` | 10,251 | `ee1e263770b2beecda27dbf2b85365c6536dd1e6f4c69f3ed5ad6451d39290b2` | D, "Frozen source: unified diff against TC-A", verbatim |
| `reference/combo/combog.py` (`ComboG`, `GATE = 1`) | 6,011 | `321c61dff43c1677722d4b52e066ed5296f08ac7b72465245f04eb04e1c143cb` | D, "Exact combog.py", verbatim |
| `contracts/Candidate.sol` (TC-A, base, unchanged) | 44,963 | `b87234c89e094f4955578417c1266129b0f96e6dfda68e3fb8866e00eeda71a2` | trunk 4eb3e98 |
| `reference/combo/twocomp.py` (unchanged, `DUAL_CUTS=2`) | 11,202 | `9d3c1833321493fb51bbde4e1b4dabc2f8978bd6d774ee2af8dc8aed13f0f0af` | trunk |
| `reference/qt1/qmref.py` (unchanged) | | `1dfc9b7a3c2237ff7a93dd9f0af54b9bdab16f2ce0a7eb00784cb4432598db92` | trunk |
| `reference/qt1/blob.bin` (unchanged) | | `3ac7cb8811ecfb6a17f499aa4e9b70dd55f7fb6432b3aec3b904e11a3dece38e` | trunk |

ComboG = TwoComp's filter and carried state (silent dual-cut cap as in TwoComp) + COMBO weighted-average offset quoting on a step's first own trade, used only when `dt <= GATE` (here `dt == 1`). Other callbacks quote as TwoComp. `GATE` is 1 in both `combog.py` and `Combo.sol`.

## P (attributed to D)

D ran Taylor's pinned `research/solved/gates.py` (plain `python3 -I`) before any policy change and reproduced it: seed 10000 gaussian+plain 443.455598, gaussian+qm 443.522608, lattice+qm 443.663520 (10001 and 10002 also listed in D, section "Platform, setup, and Gate P").

## Q (attributed to D): ComboG(1) reference vs qt1 reference, Taylor's replica, paired

| Window | n | mean_diff | se | worst5 (seed: diff) |
| --- | ---: | ---: | ---: | --- |
| choose 60000..61023 | 1024 | **+0.6370844005364295** | 0.019226759996279156 | 60210 −3.5070, 60036 −1.4310, 60326 −1.2934, 60446 −1.1194, 60734 −1.0589 |
| report 10000..12047 | 2048 | **+0.6028942685272641** | 0.013049022593029348 | 10146 −3.7595, 11062 −2.0769, 11808 −1.7740, 11376 −1.5676, 10162 −1.3574 |

se = `stdev(diff)/sqrt(n)`. GATE=1 was chosen by gas alone before these scores were looked at (D).

Re-checked here (plain `python3 -I`, stdlib, runner in README): `replica2.run(seed, ComboG('reference/qt1/blob.bin'))['edge']` gives 444.3066107552986 / 571.8761229207034 / 526.1507459263532 on 10000 / 10001 / 10002, and `QMRef` gives 443.1017411146794 on 10000. These equal D's per-seed table to its 12 decimals.

## F (attributed to D): contract fees vs `combog.ComboG`

`tools/check.py` (effective-fee comparison, reference clamped to [0, 0.1]) on seeds 70000..70049, 50 x 2,000 = **100,000 callbacks**: pass, max error **3.0968576748141574e-06 bps** (seed 70003, callback 655), pyrevm peak **203,056** gas (seed 70042), **0 OOG** on those samples. D added only diagnostic bookkeeping (max-callback index, `oog=0` field) to check.py; no tolerance, gas limit or callback count changed.

## Gas probe (attributed to D)

Mixed-path probe on five full replica runs, seeds 70000..70004, every callback first given 245,000 gas, pyrevm `gas_used`:

- **GATE=1 (shipped):** mixed dt=1 peak **203,136** (seed 70004, callback 8342), 21,500 callbacks; non-mixed peak 166,518; **0 OOG**.
- Ungated (not shipped): dt=2 208,069, up to 237,385 at dt 10..12; 0 OOG, but over D's 205,000 pyrevm budget, so larger gates were rejected.
- Runtime **22,058 bytes** (limit 24,576); solc 0.8.24, challenge compiler (optimizer 200 runs, viaIR); `amm-match validate`: PASS.

**No universal gas bound is claimed.** Zero OOG holds for the sampled replays above only; the engine limit is 245,000 per afterSwap and untested states may cost more.

## Engine diagnostic: EXCLUDED

D's engine run on seeds 9800000..9800007 (n=8, +0.4367 ± 0.1775, candidate peak 220,186) reused seeds reserved earlier in this goal. It is **excluded from fresh confirmation** and is not evidence for ComboG.

## Pending (not run by the freeze item)

- Fresh engine confirmation: Combo A 9803572..9804595, Combo B 9804596..9805619 (paired vs qt1, `gas_stats()`); TC-A gap run 9805620..9805635. Results pending.
- Independent recompilation of `Combo.sol` and re-run of F and the gas probe in a separate worker.
- Board submission is the requester's decision and action.
