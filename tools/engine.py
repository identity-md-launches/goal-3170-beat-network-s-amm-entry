#!/usr/bin/env python3
"""Paired engine arms, adapted from SP engine.py.
Credit: Taylor (gtmcknight), reference policy and replica research.
Run each contract alone versus the 30 bps VanillaStrategy; half-open seed range.
"""
import argparse
import json
import math
from pathlib import Path
import time

import amm_sim_rs
from amm_competition.competition.config import BASELINE_VARIANCE, build_base_config
from amm_competition.evm.compiler import SolidityCompiler
from check import compiled, seed_range


def vanilla():
    source = Path('contracts/src/VanillaStrategy.sol').read_text()
    result = SolidityCompiler().compile(source, contract_name='VanillaStrategy')
    if not result.success:
        raise RuntimeError(result.errors)
    return result.bytecode


def configs(start,end):
    # _build_configs seeds parameter variability with np.default_rng(i).
    # Build through end, then select assigned fresh seeds, so the config
    # for seed i is exactly the one MatchRunner would build for i.
    # Equivalent direct transcription avoids allocating 9.5M configs.
    import numpy as np
    base=build_base_config(seed=None);v=BASELINE_VARIANCE;out=[]
    for seed in range(start,end):
        rng=np.random.default_rng(seed)
        size=rng.uniform(v.retail_mean_size_min,v.retail_mean_size_max)
        rate=rng.uniform(v.retail_arrival_rate_min,v.retail_arrival_rate_max)
        sig=rng.uniform(v.gbm_sigma_min,v.gbm_sigma_max)
        out.append(amm_sim_rs.SimulationConfig(n_steps=base.n_steps,initial_price=base.initial_price,initial_x=base.initial_x,initial_y=base.initial_y,gbm_mu=base.gbm_mu,gbm_sigma=sig,gbm_dt=base.gbm_dt,retail_arrival_rate=rate,retail_mean_size=size,retail_size_sigma=base.retail_size_sigma,retail_buy_prob=base.retail_buy_prob,seed=seed))
    return out

def paired(first, second):
    a = {row['seed']: row['edge'] for row in first}
    b = {row['seed']: row['edge'] for row in second}
    if len(a) != len(first) or len(b) != len(second) or a.keys() != b.keys():
        raise ValueError('engine results have duplicate or mismatched seeds')
    diffs = [(seed, a[seed] - b[seed]) for seed in sorted(a)]
    n = len(diffs)
    mean = sum(diff for _, diff in diffs) / n
    se = math.sqrt(sum((diff - mean)**2 for _, diff in diffs) / (n - 1) / n) if n > 1 else None
    return dict(n=n, mean_diff=mean, se=se,
                worst5=[dict(seed=seed, diff=diff) for seed, diff in sorted(diffs, key=lambda item: (item[1], item[0]))[:5]])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('start', type=int)
    parser.add_argument('end', type=int)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    seed_range(parser, args.start, args.end)
    codes = {key: compiled(path) for key, path in
             (('candidate', args.candidate), ('baseline', args.baseline))}
    normalizer = vanilla()
    cfg = configs(args.start, args.end)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    out = dict(status='started', start=args.start, end=args.end,
               sha256={key: code['sha256'] for key, code in codes.items()}, arms={})
    # Exclusive creation reserves this output before either engine invocation.
    with args.output.open('x') as handle:
        json.dump(out, handle)
    started = time.time()
    for key, code in codes.items():
        amm_sim_rs.gas_stats_reset()
        arm_started = time.time()
        batch = amm_sim_rs.run_batch(list(bytes.fromhex(code['creation'])), list(normalizer), cfg, 8)
        rows = [dict(seed=r.seed, edge=r.edges['submission'],
                     normalizer_edge=r.edges['normalizer']) for r in batch.results]
        if sorted(r['seed'] for r in rows) != list(range(args.start, args.end)):
            raise ValueError('engine returned missing or duplicate seeds')
        out['arms'][key] = dict(rows=rows, gas=amm_sim_rs.gas_stats(),
                                seconds=time.time() - arm_started, sha256=code['sha256'])
        args.output.write_text(json.dumps(out))
    out.update(status='done', seconds=time.time() - started,
               paired=paired(out['arms']['candidate']['rows'], out['arms']['baseline']['rows']))
    args.output.write_text(json.dumps(out))
    print(json.dumps(out), flush=True)


if __name__ == '__main__':
    main()
