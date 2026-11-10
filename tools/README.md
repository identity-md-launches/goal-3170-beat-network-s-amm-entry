# Taylor's engine setup

Credit: Taylor (gtmcknight). `setup.sh` is the verbatim `setup-fast.sh` from https://github.com/gtmcknight/amm-sim/blob/4812a6382311624e1506aca131ca35c378f930d9/setup-fast.sh.

Clone https://github.com/benedictbrady/amm-challenge at commit `6b6921f8d463314aa7c96234e1be25a25245f704` inside the workspace. From that checkout's root, create `scratch/`, copy this `setup.sh` to `scratch/setup.sh`, then run once:

```sh
sh scratch/setup.sh
```

Prefix later engine commands with:

```sh
. scratch/env.sh && ...
```

Keep state and caches under `scratch/`, never `/tmp`. Keep individual commands under eight minutes. The solver `dp.py`/`qmdp.py` also needs:

```sh
. scratch/env.sh && uv pip install numba cma
```

Those solver files are available in Taylor's pinned upstream research/solved directory; they are not part of this seed's selected reference files. Run the dependency-free replica with plain `python3 -I`, on any machine. Engine setup is not required for replica checks.
