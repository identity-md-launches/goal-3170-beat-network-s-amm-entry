#!/usr/bin/env python3
"""Gate F effective-fee replay, adapted from SP replay.py.
Credit: Taylor (gtmcknight), Gaussian filter, qm tables and replica.
Seed ranges are half-open. Run from a prepared amm-challenge checkout.
"""
import argparse
import hashlib
import importlib
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
HERE = Path.cwd() / 'scratch'


def compiled(path):
    from amm_competition.evm.compiler import SolidityCompiler
    source = Path(path).read_text()
    digest = hashlib.sha256(source.encode()).hexdigest()
    HERE.mkdir(parents=True, exist_ok=True)
    cache = HERE / (digest + '.json')
    if cache.exists():
        return json.loads(cache.read_text())
    start = time.time()
    result = SolidityCompiler().compile(source)
    if not result.success:
        raise RuntimeError(result.errors)
    data = dict(creation=result.bytecode.hex(), runtime=result.deployed_bytecode.hex(),
                sha256=digest, seconds=time.time() - start)
    cache.write_text(json.dumps(data))
    print('compiled', digest, len(result.deployed_bytecode), data['seconds'], flush=True)
    return data


def call(executor, values, init=False):
    data = bytes.fromhex('837aef47' if init else 'c2babb57')
    data += b''.join(int(v).to_bytes(32, 'big') for v in values)
    out = executor.evm.message_call(caller=executor.CALLER_ADDRESS,
                                   to=executor.deployed_address,
                                   calldata=data, value=0, gas=245000)
    if len(out) != 64:
        raise RuntimeError(('invalid result', out))
    return out


def fees(out):
    return [int.from_bytes(out[k:k+32], 'big') / 1e18 for k in (0, 32)]


class Stop(Exception):
    pass


def replay(seed, code, policy_class, blob):
    from amm_competition.evm.executor import EVMStrategyExecutor
    import replica2 as R
    key = 'candidate'
    executor = EVMStrategyExecutor(bytes.fromhex(code['creation']))
    policy = policy_class(str(blob))
    original_init = policy.init
    original_trade = policy.on_trade
    n = 0
    maximum = peak = total = 0
    digest = hashlib.sha256()

    def compare(out, reference):
        nonlocal maximum
        error = max(abs(a - R.clampf(b)) * 1e4 for a, b in zip(fees(out), reference))
        if error > .01:
            raise AssertionError((seed, n, key, error, fees(out), reference))
        maximum = max(maximum, error)

    def initialize(*args):
        reference = original_init(*args)
        compare(call(executor, [100 * 10**18, 10000 * 10**18], True), reference)
        return reference

    def record(*args):
        nonlocal n, peak, total
        reference = original_trade(*args)
        buy, ax, ay, timestamp, x, y, *_ = args
        out = call(executor, [buy, int(ax * 1e18), int(ay * 1e18),
                              timestamp, int(x * 1e18), int(y * 1e18)])
        digest.update(out)
        gas = executor.evm.result.gas_used
        peak = max(peak, gas)
        total += gas
        compare(out, reference)
        n += 1
        if n == 2000:
            raise Stop()
        return reference

    policy.init = initialize
    policy.on_trade = record
    try:
        R.run(seed, policy)
    except Stop:
        pass
    if n != 2000:
        raise AssertionError((seed, 'insufficient callbacks', n))
    return dict(seed=seed, n=n, max_error_bps={key: maximum}, peak={key: peak},
                sum_gas={key: total}, sha256={key: digest.hexdigest()})


def seed_range(parser, start, end):
    if not 0 <= start < end:
        parser.error('require 0 <= start < end (end is exclusive)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('contract', type=Path)
    parser.add_argument('reference', help='module.Class, e.g. qmref.QMRef')
    parser.add_argument('start', type=int)
    parser.add_argument('end', type=int)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    seed_range(parser, args.start, args.end)
    for directory in ('reference/taylor', 'reference/qt1', 'reference/twocomp', 'reference/mix'):
        sys.path.insert(0, str(ROOT / directory))
    module, name = args.reference.rsplit('.', 1)
    policy_class = getattr(importlib.import_module(module), name)
    code = compiled(args.contract)
    rows = []
    start = time.time()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    for seed in range(args.start, args.end):
        row = replay(seed, code, policy_class, ROOT / 'reference/qt1/blob.bin')
        rows.append(row)
        print(json.dumps(row), flush=True)
        args.output.write_text(json.dumps(dict(rows=rows, seconds=time.time() - start)))


if __name__ == '__main__':
    main()
