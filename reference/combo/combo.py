"""COMBO = two-component filter + weighted-average offset quoting.
Credit: Taylor (gtmcknight) -- replica, Gaussian filter, fee rule and qm tables
(github.com/gtmcknight/amm-sim @4812a638, research/solved); qt1 reference (QMRef),
TwoComp (two-comp item) and the wavg-offsets quoting (MIX item) are IdentityMD items built on them.
Standard library only. Needs twocomp.py (the TC artifact's Code block, unmodified) beside it.
usage: from combo import Combo; Combo('blob.bin') is a replica2 policy (wants_j).

Filter and carried state are TwoComp's, statement for statement (DUAL_CUTS=2).
Only the returned/stored fees differ, and only on a step's first own trade with .005 < pi < .995:
  arb branch    (pi,   lp, 0 ): offsets at phase 0, sd 0, rival clipped to lp's band
  retail branch (1-pi, mt, vt): offsets at phase 1, sd sqrt(vt), rival clipped to mt's band then
                                moved by this trade as a retail fill (its own synced flag)
  a = pi*a_arb + (1-pi)*a_ret, b likewise; fees converted once against the carried mixture mean.
Both branches start from the pre-step rival estimate. Nothing is tuned.
"""
import math
from twocomp import TwoComp, SIG2, LD_M, LD_S, MAXF, phi, trunc


class Combo(TwoComp):
    def __init__(self, blob_path):
        super().__init__(blob_path)
        self.new_path_calls = 0

    def lookup_offsets(self, w, w2, phs, sd, synced):
        """QMRef.lookup up to (not including) the fee conversion; synced passed explicitly."""
        S = self.S; k = 0
        while k < len(S) - 2 and sd >= S[k + 1]: k += 1
        tt = min(1.0, max(0.0, (sd - S[k]) / (S[k + 1] - S[k])))
        tag = '0c' if phs == 0 else (str(phs) + ('s' if synced else 'c'))
        A, B = self.T.A[tag], self.T.B[tag]
        pw = min(self.NW - 1.0, max(0.0, w / self.h + self.W0))
        l2 = w2 / self.h
        if phs == 0:
            l2 = min(self.FB, max(-self.FB, l2)); p2 = l2 + self.FB; n2 = 2 * self.FB + 1
        else:
            p2 = self._pos2(l2); n2 = len(self.W2L)
        i = min(int(pw), self.NW - 2); j = min(int(p2), n2 - 2); f = pw - i; g = p2 - j
        def bl(Tb):
            return (Tb[i][j] * (1 - f) + Tb[i + 1][j] * f) * (1 - g) + (Tb[i][j + 1] * (1 - f) + Tb[i + 1][j + 1] * f) * g
        a = bl(A[k]) * (1 - tt) + bl(A[k + 1]) * tt
        b = bl(B[k]) * (1 - tt) + bl(B[k + 1]) * tt
        return a, b

    def on_trade(self, is_buy, ax, ay, t, x, y, arb=False, p=100., s2=100., j=0):
        s = y / x; dt = t - self.tlast; is_arb = False; mix = None
        if dt >= 1:
            # ---- TwoComp filter, unchanged ----
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
                ret = [(w / Z, m, v) for w, m, v in retail]
                mt, vt = self.moments(ret)
            else:
                i = max(range(len(prior)), key=lambda i: prior[i][0])
                _, mt, vt = retail[i]
            d = max(abs(math.log(s / self.sp)), 1e-9)
            lr = Z * .26 * phi((math.log(d) - LD_M) / LD_S) / (d * LD_S)
            pi = la / (la + lr) if la + lr > 0 else 0.
            is_arb = pi > .5
            if .005 < pi < .995:
                self.comp = [(pi, lp, 0.), (1 - pi, mt, vt)]
                # ---- MIX quoting inputs: each branch starts from the pre-step rival estimate ----
                pa = math.exp(lp); pr = math.exp(mt); old_s2 = self.s2h
                s2_arb = max(pa * .997, min(pa / .997, old_s2))
                s2_ret = max(pr * .997, min(pr / .997, old_s2))
                cand_ret = s * (1 - self.fb) / .997 if is_buy else s * .997 / (1 - self.fa)
                synced_ret = (cand_ret < s2_ret) if is_buy else (cand_ret > s2_ret)
                if synced_ret: s2_ret = cand_ret
                mix = (pi, lp, mt, vt, s2_arb, s2_ret, synced_ret)
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
        ls = math.log(s)
        if mix is None:      # every other callback: TwoComp's quote
            fb, fa = self.lookup((ls - self.m) * 1e4, (math.log(self.s2h) - self.m) * 1e4, ph, math.sqrt(self.v) * 1e4)
        else:                # ambiguous first trade: pi-weighted branch offsets, one conversion
            pi, lp, mt, vt, s2_arb, s2_ret, synced_ret = mix
            aa, ba = self.lookup_offsets((ls - lp) * 1e4, (math.log(s2_arb) - lp) * 1e4, 0, 0., False)
            ar, br = self.lookup_offsets((ls - mt) * 1e4, (math.log(s2_ret) - mt) * 1e4, 1, math.sqrt(vt) * 1e4, synced_ret)
            a = pi * aa + (1 - pi) * ar; b = pi * ba + (1 - pi) * br
            w = (ls - self.m) * 1e4
            fa = 1.0 - math.exp(-(a - w) * 1e-4) if a > w else 0.0
            fb = 1.0 - math.exp(-(b + w) * 1e-4) if b > -w else 0.0
            self.new_path_calls += 1
        self.fb, self.fa = min(MAXF, max(0.0, fb)), min(MAXF, max(0.0, fa))
        return fb, fa
