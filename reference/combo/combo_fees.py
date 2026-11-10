"""COMBO: TwoComp's two-component filter + wavg-fees quoting at ambiguous first trades.
Credit: Taylor (gtmcknight) for the Gaussian filter, solved tables and replica (amm-sim research/solved);
qt1's reference (qmref) and TwoComp (twocomp.py = TC's Code block, unchanged). Stdlib only.
usage: from combo import Combo; Combo('blob.bin') is a replica2 policy."""
import math
from twocomp import TwoComp, trunc, phi, LD_M, LD_S, MAXF


class Combo(TwoComp):
    def __init__(self, blob_path):
        super().__init__(blob_path)
        self.new_path_calls = 0

    def on_trade(self, is_buy, ax, ay, t, x, y, arb=False, p=100., s2=100., j=0):
        s = y / x; dt = t - self.tlast; is_arb = False
        mix_fees = None
        if dt >= 1:
            self.cnt = 0
            lo = math.log(self.sp * (1 - self.fb)); hi = math.log(self.sp / (1 - self.fa))
            prior = self.propagate(dt, lo, hi)
            lp = math.log(s * (1 - self.fb)) if is_buy else math.log(s / (1 - self.fa))
            la = 0.0; Z = 0.0; retail = []
            for w, m, v in prior:
                sd = math.sqrt(v)
                la += w * phi((lp - m) / sd) / sd
                z, mt, vt = trunc(m, v, lo, hi)
                Z += w * z
                retail.append((w * z, mt, vt))
            if Z > 1e-300:
                mt, vt = self.moments([(w / Z, m, v) for w, m, v in retail])
            else:
                i = max(range(len(prior)), key=lambda i: prior[i][0])
                _, mt, vt = retail[i]
            d = max(abs(math.log(s / self.sp)), 1e-9)
            lr = Z * .26 * phi((math.log(d) - LD_M) / LD_S) / (d * LD_S)
            pi = la / (la + lr) if la + lr > 0 else 0.
            is_arb = pi > .5
            if .005 < pi < .995:
                # wavg-fees quoting: one lookup per branch, branches = TwoComp components
                old_synced = self.synced
                pa = math.exp(lp)
                ra = max(pa * .997, min(pa / .997, self.s2h))
                self.synced = False
                fba, faa = self.lookup((math.log(s) - lp) * 1e4, (math.log(ra) - lp) * 1e4, 0, 0.)
                pr = math.exp(mt)
                rr = max(pr * .997, min(pr / .997, self.s2h))
                cand = s * (1 - self.fb) / .997 if is_buy else s * .997 / (1 - self.fa)
                if (cand < rr) if is_buy else (cand > rr):
                    rr = cand; self.synced = True
                fbr, far = self.lookup((math.log(s) - mt) * 1e4, (math.log(rr) - mt) * 1e4,
                                       1, math.sqrt(vt) * 1e4)
                self.synced = old_synced
                mix_fees = (pi * fba + (1 - pi) * fbr, pi * faa + (1 - pi) * far)
                self.new_path_calls += 1
                self.comp = [(pi, lp, 0.), (1 - pi, mt, vt)]
            elif is_arb:
                self.comp = [(1.0, lp, 0.)]
            else:
                self.comp = [(1.0, mt, vt)]
            self.m, self.v = self.moments(self.comp)
            pe = math.exp(self.m)
            self.s2h = max(pe * .997, min(pe / .997, self.s2h))
            self.synced = False
        if not is_arb:
            cand = s * (1 - self.fb) / .997 if is_buy else s * .997 / (1 - self.fa)
            if (cand < self.s2h) if is_buy else (cand > self.s2h):
                self.s2h = cand; self.synced = True
            self.cnt += 1
            ph = 1 if self.cnt == 1 else 2
        else:
            ph = 0
        self.tlast = t; self.sp = s
        if mix_fees is None:
            fb, fa = self.lookup((math.log(s) - self.m) * 1e4, (math.log(self.s2h) - self.m) * 1e4,
                                 ph, math.sqrt(self.v) * 1e4)
        else:
            fb, fa = mix_fees
        self.fb, self.fa = min(MAXF, max(0.0, fb)), min(MAXF, max(0.0, fa))
        return fb, fa
