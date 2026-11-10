"""wavg-offsets variant of qt1, based on Taylor (gtmcknight)'s Gaussian filter
and qm tables. The ambiguous first trade quotes both posterior components.
Standard library only. Usage: from mix import QMRef; QMRef('blob.bin').
Init fees = real.py's init: the full plain pol_mid table at (0,0,0) = 0.002823606104386589 each.
"""
import math, struct

SIG2 = .000945 ** 2
LD_M, LD_S = math.log(11.12e-4), 1.176
INIT = 0.002823606104386589
MAXF = 0.1


def phi(x): return math.exp(-.5 * x * x) / 2.5066282746310002
def Phi(x): return .5 * (1 + math.erf(x / 1.4142135623730951))


def trunc(m, v, lo, hi):
    if v <= 0: return float(lo <= m <= hi), m, 0.
    sd = math.sqrt(v); a = (lo - m) / sd; b = (hi - m) / sd; z = Phi(b) - Phi(a)
    if z < 1e-12: return z, lo if m < lo else hi, v * .25
    pa, pb = phi(a), phi(b); r = (pa - pb) / z
    return z, m + sd * r, max(0, v * (1 + (a * pa - b * pb) / z - r * r))


def parse(blob):
    o = [0]
    def rd(fmt):
        v = struct.unpack_from('<' + fmt, blob, o[0]); o[0] += struct.calcsize('<' + fmt); return v
    assert blob[:4] == b'QMS1'; o[0] = 4
    form, ntab, nw, w0, h, ns = rd('BBHHBB'); assert form == 3
    S = list(rd('%dB' % ns)); n2 = rd('B')[0]; W2L = list(rd('%dh' % n2)); fb = rd('B')[0]
    tabs = []
    for _ in range(ntab):
        nr, nc, nk = rd('BBB')
        kr = list(rd('%dH' % (nr - 4))); kc = list(rd('%dH' % (nc - 4))); ks = list(rd('%dH' % (nk - 4)))
        assert nk == 4 and not ks
        tabs.append([nr, nc, nk, kr, kc])
    for t in tabs:
        t.append(list(rd('%dh' % (t[0] * t[1] * t[2]))))
    assert o[0] == len(blob)
    return dict(NW=nw, W0=w0, H=float(h), S=[float(s) for s in S], W2L=[float(v) for v in W2L], FB=fb, tabs=tabs)


def basis(knots, x):
    """all cubic B-spline basis values at x (Cox-de Boor recursion), right end included"""
    t = knots; n = len(t) - 4
    B = [1.0 if t[m] <= x < t[m + 1] else 0.0 for m in range(len(t) - 1)]
    if x >= t[-1]:
        last = max(m for m in range(len(t) - 1) if t[m] < t[m + 1]); B = [0.0] * (len(t) - 1); B[last] = 1.0
    for d in range(1, 4):
        Bn = [0.0] * (len(t) - 1 - d)
        for m in range(len(t) - 1 - d):
            a = t[m + d] - t[m]; b = t[m + d + 1] - t[m + 1]
            if a > 0: Bn[m] += (x - t[m]) / a * B[m]
            if b > 0: Bn[m] += (t[m + d + 1] - x) / b * B[m + 1]
        B = Bn
    return B[:n]


def surfaces(P):
    """F[t][level][row][col] = max(0, spline) at the grid nodes, in bps"""
    out = []
    for ti, (nr, nc, nk, kr, kc, C) in enumerate(P['tabs']):
        ncol = 2 * P['FB'] + 1 if ti == 0 else len(P['W2L'])
        Kr = [0.0] * 4 + [v / 64 for v in kr] + [P['NW'] - 1.0] * 4
        Kc = [0.0] * 4 + [v / 64 for v in kc] + [ncol - 1.0] * 4
        Ks = [0.0] * 4 + [len(P['S']) - 1.0] * 4
        Br = [basis(Kr, i) for i in range(P['NW'])]; Bc = [basis(Kc, j) for j in range(ncol)]
        Bs = [basis(Ks, l) for l in range(len(P['S']))]
        F = []
        for l in range(len(P['S'])):
            D = [[sum(Bs[l][s] * C[(s * nr + r) * nc + c] for s in range(nk)) / 8.0 for c in range(nc)] for r in range(nr)]
            E = [[sum(D[r][c] * Bc[j][c] for c in range(nc)) for j in range(ncol)] for r in range(nr)]
            F.append([[max(0.0, sum(Br[i][r] * E[r][j] for r in range(nr))) for j in range(ncol)] for i in range(P['NW'])])
        out.append(F)
    return out


class Tables:
    """A/B exactly as qms_decode.to_qm writes them (rounded to 6 decimals)"""
    def __init__(self, blob):
        P = parse(blob); self.P = P
        NW = P['NW']; w = [(i - P['W0']) * P['H'] for i in range(NW)]
        self.A = {}; self.B = {}
        for tag, F in zip(['0c', '1s', '1c', '2s', '2c'], surfaces(P)):
            A = [[[round(F[l][i][j] + w[i], 6) for j in range(len(F[l][i]))] for i in range(NW)] for l in range(len(F))]
            self.A[tag] = A
            self.B[tag] = [[row[::-1] for row in A[l][::-1]] for l in range(len(A))]


class QMRef:
    wants_j = True
    _cache = {}
    def __init__(self, blob_path):
        if blob_path not in QMRef._cache: QMRef._cache[blob_path] = Tables(open(blob_path, 'rb').read())
        self.T = QMRef._cache[blob_path]; P = self.T.P
        self.S = P['S']; self.W0 = P['W0']; self.NW = P['NW']; self.h = P['H']; self.FB = P['FB']; self.W2L = P['W2L']
        self.m = math.log(100); self.v = 0.; self.tlast = 0; self.cnt = 0; self.s2h = 100.; self.fb = self.fa = .003
        self.sp = 100.; self.synced = False
        self.new_path_calls = 0
    def _pos2(self, v):
        W = self.W2L; n = len(W)
        if v <= W[0]: return 0.0
        if v >= W[n - 1]: return float(n - 1)
        lo, hi = 0, n - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if W[mid] <= v: lo = mid
            else: hi = mid
        return lo + (v - W[lo]) / (W[hi] - W[lo])
    def lookup_offsets(self, w, w2, phs, sd, synced=None):
        S = self.S; k = 0
        while k < len(S) - 2 and sd >= S[k + 1]: k += 1
        tt = min(1.0, max(0.0, (sd - S[k]) / (S[k + 1] - S[k])))
        tag = '0c' if phs == 0 else (str(phs) + ('s' if (self.synced if synced is None else synced) else 'c'))
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
    def fees_from_offsets(self, a, b, w):
        fa = 1.0 - math.exp(-(a - w) * 1e-4) if a > w else 0.0
        fb = 1.0 - math.exp(-(b + w) * 1e-4) if b > -w else 0.0
        return fb, fa
    def lookup(self, w, w2, phs, sd):
        a, b = self.lookup_offsets(w, w2, phs, sd)
        return self.fees_from_offsets(a, b, w)
    def init(self, *args):
        self.fb = self.fa = INIT; return INIT, INIT
    def on_trade(self, is_buy, ax, ay, t, x, y, arb=False, p=100., s2=100., j=0):
        s = y / x; dt = t - self.tlast; is_arb = False; mix_parts = None
        if dt >= 1:
            self.cnt = 0; lo = math.log(self.sp * (1 - self.fb)); hi = math.log(self.sp / (1 - self.fa)); m, v = self.m, self.v
            for _ in range(min(dt - 1, 12)):
                v += SIG2; _, m, v = trunc(m, v, lo, hi)
            v += SIG2
            lp = math.log(s * (1 - self.fb)) if is_buy else math.log(s / (1 - self.fa)); sd = math.sqrt(v)
            la = phi((lp - m) / sd) / sd; Z, mt, vt = trunc(m, v, lo, hi); d = max(abs(math.log(s / self.sp)), 1e-9)
            lr = Z * .26 * phi((math.log(d) - LD_M) / LD_S) / (d * LD_S)
            pi = la / (la + lr) if la + lr > 0 else 0.; is_arb = pi > .5
            if .005 < pi < .995:
                m2 = pi * lp + (1 - pi) * mt; self.m, self.v = m2, pi * (lp - m2) ** 2 + (1 - pi) * (vt + (mt - m2) ** 2)
                # Each hypothesis starts from the same pre-step rival estimate.
                pa = math.exp(lp); pr = math.exp(mt); old_s2 = self.s2h
                s2_arb = max(pa * .997, min(pa / .997, old_s2))
                s2_ret = max(pr * .997, min(pr / .997, old_s2))
                cand_ret = s * (1 - self.fb) / .997 if is_buy else s * .997 / (1 - self.fa)
                synced_ret = (cand_ret < s2_ret) if is_buy else (cand_ret > s2_ret)
                if synced_ret: s2_ret = cand_ret
                mix_parts = (pi, lp, mt, vt, s2_arb, s2_ret, synced_ret)
            elif is_arb: self.m, self.v = lp, 0.
            else: self.m, self.v = mt, vt
            pe = math.exp(self.m); self.s2h = max(pe * .997, min(pe / .997, self.s2h)); self.synced = False
        if not is_arb:
            cand = s * (1 - self.fb) / .997 if is_buy else s * .997 / (1 - self.fa)
            if (cand < self.s2h) if is_buy else (cand > self.s2h): self.s2h = cand; self.synced = True
            self.cnt += 1; ph = 1 if self.cnt == 1 else 2
        else: ph = 0
        self.tlast = t; self.sp = s
        if mix_parts is None:
            fb, fa = self.lookup((math.log(s) - self.m) * 1e4, (math.log(self.s2h) - self.m) * 1e4, ph, math.sqrt(self.v) * 1e4)
        else:
            pi, lp, mt, vt, s2_arb, s2_ret, synced_ret = mix_parts
            log_s = math.log(s)
            aa, ba = self.lookup_offsets((log_s - lp) * 1e4, (math.log(s2_arb) - lp) * 1e4, 0, 0.)
            ar, br = self.lookup_offsets((log_s - mt) * 1e4, (math.log(s2_ret) - mt) * 1e4, 1, math.sqrt(vt) * 1e4, synced_ret)
            a = pi * aa + (1 - pi) * ar; b = pi * ba + (1 - pi) * br
            fb, fa = self.fees_from_offsets(a, b, (log_s - self.m) * 1e4)
            self.new_path_calls += 1
        self.fb, self.fa = min(MAXF, max(0.0, fb)), min(MAXF, max(0.0, fa))
        return fb, fa
