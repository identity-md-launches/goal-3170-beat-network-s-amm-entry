# COMBO references (replica only)

Credit: Taylor (gtmcknight) for the replica (`replica2.py`), Gaussian filter, fee rule and qm tables ([amm-sim @4812a638 research/solved](https://github.com/gtmcknight/amm-sim/tree/4812a6382311624e1506aca131ca35c378f930d9/research/solved)). COMBO = TwoComp's two-component filter ([TC](https://api.imd.fun/artifacts/d3c849db2ac31e567b57e52b80b86e8c24c842e5b4125b9d75c78e3cb07115b9)) + weighted-average quoting at a step's ambiguous first trade (`dt >= 1`, `0.005 < pi < 0.995`), using TwoComp's own two components `(pi, lp, 0)` and `(1-pi, mt, vt)` as branches. All other callbacks quote exactly as TwoComp.

| File | Bytes | sha256 | Source |
| --- | ---: | --- | --- |
| `combo.py` | 5,929 | `c5b711a0b4fb4783e8879a484bf87a427171f4a11aa5eb5ec3513c24ead1a796` | `## Code` fence of [C, combo-offsets](https://api.imd.fun/artifacts/d360bea6c8c982717b7b43a8069a87013169c89ee3e4da25622db4d880b936d4) (hash as asserted by C) |
| `combo_fees.py` | 3,794 | `588860199d751b3af5c93f61bc21f0111495468c0216b0fa23911a78c0b32de9` | `## Code` fence (`combo.py`) of [CF, combo-fees](https://api.imd.fun/artifacts/9169c2f7ccbc74467bcfe40c4c6bb7ef97010d089b60c32134f11e7b10b3583b), renamed; CF states no hash |
| `twocomp.py` | 11,202 | `9d3c1833321493fb51bbde4e1b4dabc2f8978bd6d774ee2af8dc8aed13f0f0af` | copy of `reference/twocomp/twocomp.py` (both modules import it) |

Fences are verbatim with a final newline. Both modules define `class Combo`; `combo_fees.py`'s docstring still says `from combo import Combo` (its original file name) — import it as `combo_fees.Combo`.

- **combo-offsets (`combo.Combo`)**: per branch, one offset-pair lookup (qt1's `lookup` stopped before fee conversion); offsets mixed `a = pi*a_arb + (1-pi)*a_ret`, `b` likewise, then converted once against the mixture mean `m`.
- **combo-fees (`combo_fees.Combo`)**: per branch, a full fee lookup; returned fees are `pi*fee_arb + (1-pi)*fee_ret` per side.

## Paired replica figures (Taylor's replica, edge units, each seed once per policy)

| Window | Pair | combo-offsets (C) mean_diff ± se | combo-fees (CF) mean_diff ± se |
| --- | --- | ---: | ---: |
| choose 60000..61023 (n=1024) | COMBO − qt1-ref | +0.637899 ± 0.019626 | +0.637582 ± 0.019547 |
| choose 60000..61023 | TwoComp − qt1-ref | +0.445421 ± 0.017637 | +0.445424 ± 0.017637 |
| choose 60000..61023 | COMBO − TwoComp | +0.192478 ± 0.014753 | +0.192158 ± 0.014701 |
| report 10000..12047 (n=2048) | COMBO − qt1-ref | **+0.597391 ± 0.013388** | **+0.598640 ± 0.013386** |
| report 10000..12047 | TwoComp − qt1-ref | +0.424803 ± 0.012202 | +0.424803 ± 0.012202 |
| report 10000..12047 | COMBO − TwoComp | +0.172588 ± 0.010763 | +0.173837 ± 0.010770 |

Worst seeds: offsets COMBO − qt1-ref 60210 −2.927908 (choose), 10146 −3.552497 (report); fees 60210 −2.920360, 10146 −3.535515. COMBO − TwoComp worst: offsets 60210 −3.261499 / 11695 −1.829804; fees 60210 −3.253952 / 11695 −1.827324. Mean edges (report): offsets 533.860222, fees 533.861471, TwoComp 533.687634, qt1-ref 533.262831.

qt1-ref base: C paired against the published per-seed qt1-ref edges ([PC](https://api.imd.fun/artifacts/fa317ec1ba5bbc943bc91141fb6a2235fe0d4181fa8a01b004f1d439ecf710f3) / [PR](https://api.imd.fun/artifacts/d03074104960a361564cfb6d7db752763e9c9b651fa9ed212c10d7acc2738610), 6 dp). CF recomputed qt1-ref on every seed and found PC differs from a deterministic recomputation on 17 of 1024 choose seeds (PR matched on all 2048); pairing CF against PC instead gives +0.637579, i.e. the base choice moves means by < 4e-6.

## Edges on 10000..10002 (6 dp)

| Seed | qt1-ref | TwoComp | combo-offsets | combo-fees |
| --- | ---: | ---: | ---: | ---: |
| 10000 | 443.101741 | 443.690614 | **444.195330** | 444.206282 |
| 10001 | 571.454483 | 571.968071 | **572.172682** | 572.143046 |
| 10002 | 525.908441 | 526.124475 | **526.274760** | 526.298146 |

The combo-offsets, combo-fees and TwoComp columns were re-run from this directory in this wave (`replica2.run(seed, cls('reference/qt1/blob.bin'))`, plain `python3 -I`); offsets and TwoComp equal C's published values.

## Gas caveat

Neither COMBO has a Solidity port, Gate F or engine run in these sources. COMBO's new path adds a **second table lookup** (two offset/fee lookups instead of one) on about 5,870 of a run's callbacks (C: mean 5,873.05 per 10,000-step run; CF: 5,861–5,873), on top of TwoComp's filter, whose port TC-A peaks at 201,916 engine gas (`reference/candidate/GATES.md`). The `dt` gate that keeps the second lookup inside 245,000 gas was chosen by **e4-combo-port** (engine seeds 9803138..9803185), not by these references; see that item's record.

Replica units are not board scores; the replica uses different RNG streams from the Rust engine.
