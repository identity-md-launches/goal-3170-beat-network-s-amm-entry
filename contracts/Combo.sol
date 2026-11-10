// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {AMMStrategyBase} from "./AMMStrategyBase.sol";
import {TradeInfo} from "./IAMMStrategy.sol";
// COMBO offset quoting port; credit Taylor (gtmcknight) for replica and solved policy.
// Two-component posterior port; credit Taylor (gtmcknight) for policy, filter and tables.
// Policy: Taylor's (gtmcknight) solved game, amm-sim 4812a638, research/solved: Gaussian filter (real.py) + qm tables
// (qm_k1e-5.json, +3.77 vs HA on Taylor's replica). Filter, state and timing from trim-1 / port-3.
// Fees: real.py RealPolicy.lookup over the qm-spline decoded tables (QMS1 blob sha256 3ac7cb88..., 10,167 B):
// per table one 3-D cubic B-spline (row, column, sd level), clamped knots, coefficients int16 in 1/8 bps.
// The contract evaluates the spline at the 8 surrounding grid nodes (2 rows x 2 columns x 2 sd levels) with
// Cox-de Boor bases computed at runtime, clamps each node fee at 0, then interpolates bilinearly and linearly in sd
// exactly as real.py reads the decoded JSON. Bid side = point mirror of the ask surface (row 320-i, column last-j).
// Coefficient words are PUSH32 immediates written to memory: 4 lanes x 64 bits per word, lane = 4 int16 sd coefficients.
// Gas trim: scalar node sums, shared mirrored knot geometry, and four packed state words.
// Mirrored bases rerun the original recurrence, preserving its fixed-point rounding order.
// Knot words: interior knots as uint16 in 1/64 grid units (W[0..1] rows, W[2] columns).
// Taylor source: https://github.com/gtmcknight/amm-sim/tree/4812a6382311624e1506aca131ca35c378f930d9/research/solved
contract Strategy is AMMStrategyBase {
    int256 constant U=1e18;
    uint256 constant GATE=1;
    int256 constant LN2=693147180559945309;
    struct Belief { int256 m; int256 v; int256 fb; int256 fa; int256 sp; int256 r; uint256 t; uint256 cnt; bool sy; int256 pi; int256 lp; int256 mt; int256 vt; }
    function getName() external pure override returns(string memory) { unchecked {return "TaylorComboGQmTrim2";} }
    function mul(int256 a,int256 b) internal pure returns(int256){ unchecked {return a*b/U;} }
    function divi(int256 a,int256 b) internal pure returns(int256){ unchecked {return a*U/b;} }
    function ab(int256 x) internal pure returns(int256){ unchecked {return x<0?-x:x;} }
    function clip(int256 x,int256 a,int256 b) internal pure returns(int256){ unchecked {return x<a?a:(x>b?b:x);} }
    function ln(int256 x) internal pure returns(int256 z){ unchecked {
        require(x>0); int256 k;
        while(x< U){x*=2;k--;}
        while(x>=2*U){x/=2;k++;}
        // Reduce to [1/sqrt(2),sqrt(2)]; |y| <= 0.171573.
        if(x>1414213562373095048){x/=2;k++;}
        int256 y=divi(x-U,x+U); int256 y2=mul(y,y); int256 q=y; z=y;
        q=mul(q,y2);z+=q/3;
        q=mul(q,y2);z+=q/5;
        q=mul(q,y2);z+=q/7;
        q=mul(q,y2);z+=q/9;
        q=mul(q,y2);z+=q/11;
        q=mul(q,y2);z+=q/13;
        q=mul(q,y2);z+=q/15;
        q=mul(q,y2);z+=q/17;
        q=mul(q,y2);z+=q/19;
        return 2*z+k*LN2;
    } }
    function exp(int256 x) internal pure returns(int256){ unchecked {
        if(x< -42*U)return 0; require(x<60*U);
        int256 k=(x>=0?x+LN2/2:x-LN2/2)/LN2; int256 r=x-k*LN2;
        int256 r2=mul(r,r);
        int256 even=665280*U+mul(r2,75600*U+mul(r2,840*U+r2));
        int256 odd=mul(r,332640*U+mul(r2,10080*U+mul(r2,42*U)));
        int256 s=divi(even+odd,even-odd);
        return k>=0?s*int256(uint256(1)<<uint256(k)):s/int256(uint256(1)<<uint256(-k));
    } }
    function root(int256 x) internal pure returns(int256){ unchecked {
        if(x<=0)return 0; uint256 n=uint256(x)*1e18;uint256 z=n;uint256 r=1;
        if(z>>128>0){z>>=128;r<<=64;} if(z>>64>0){z>>=64;r<<=32;}
        if(z>>32>0){z>>=32;r<<=16;} if(z>>16>0){z>>=16;r<<=8;}
        if(z>>8>0){z>>=8;r<<=4;} if(z>>4>0){z>>=4;r<<=2;} if(z>>2>0){r<<=1;}
        for(uint256 i=0;i<7;i++)r=(r+n/r)/2;
        return int256(r<n/r?r:n/r);
    } }
    function pdf(int256 x) internal pure returns(int256){ unchecked {if(ab(x)>10*U)return 0;return divi(exp(-mul(x,x)/2),2506628274631000200);} }
    // Hart rational normal tail approximation; erf(x)=2*Phi(x*sqrt(2))-1.
    function cdf(int256 x,int256 density) internal pure returns(int256){ unchecked {
        int256 y=ab(x);if(y>8*U)return x>0?U:int256(0);
        int256 n=35262496599891000;
        n=mul(n,y)+700383064443688000;n=mul(n,y)+6373962203531650000;
        n=mul(n,y)+33912866078383000000;n=mul(n,y)+112079291497871000000;
        n=mul(n,y)+221213596169931000000;n=mul(n,y)+220206867912376000000;
        int256 d=88388347648318400;
        d=mul(d,y)+1755667163182640000;d=mul(d,y)+16064177579207000000;
        d=mul(d,y)+86780732202946100000;d=mul(d,y)+296564248779674000000;
        d=mul(d,y)+637333633378831000000;d=mul(d,y)+793826512519948000000;
        d=mul(d,y)+440413735824752000000;
        int256 tail=(density*2506628274631000200/U)*n/d;return x>0?U-tail:tail;
    } }
    function trunc(int256 m,int256 v,int256 lo,int256 hi) internal pure returns(int256,int256,int256){
        return truncSD(m,v,lo,hi,root(v));
    }
    function truncSD(int256 m,int256 v,int256 lo,int256 hi,int256 sd) internal pure returns(int256 Z,int256 mt,int256 vt){ unchecked {
        if(v<=0)return (lo<=m&&m<=hi?U:int256(0),m,0);
        int256 a=divi(lo-m,sd);int256 b=divi(hi-m,sd);
        int256 pa=pdf(a);int256 pb=pdf(b);
        Z=cdf(b,pb)-cdf(a,pa);
        if(Z<1e6)return(Z,m<lo?lo:hi,v/4);
        int256 r=divi(pa-pb,Z);
        mt=m+mul(sd,r);vt=mul(v,U+divi(mul(a,pa)-mul(b,pb),Z)-mul(r,r));if(vt<0)vt=0;
    } }
    uint256 constant K64=15625000000000000; // U/64: knots are stored in 1/64 grid units
    uint256 constant SL=0x221a14100c080400;    // S levels 0,4,8,12,16,20,26,34 bps, byte k
    uint256 constant W2=0xa08264503c32281e1914110e0c0b0a090807060504030201;  // |W2L[i]| for i<24 (grid units), byte 23-i
    function S(uint256 k) internal pure returns(int256){ unchecked {return int256((SL>>(8*k))&0xff)*U;} }
    function w2l(uint256 idx) internal pure returns(int256){ unchecked {
        if(idx==24)return 0; bool neg=idx<24; if(!neg)idx=48-idx;
        int256 v=int256((W2>>(8*(23-idx)))&0xff)*U; return neg?-v:v;
    } }
    function pos2(int256 l2) internal pure returns(int256){ unchecked {
        if(l2<= -160*U)return 0; if(l2>=160*U)return 48*U;
        uint256 lo;uint256 hi=48;
        while(hi-lo>1){uint256 mid=(lo+hi)>>1;if(w2l(mid)<=l2)lo=mid;else hi=mid;}
        int256 wl=w2l(lo);return int256(lo)*U+(l2-wl)*U/(w2l(hi)-wl);
    } }
    function kn(uint256 w0,uint256 w1,uint256 ni,int256 lastU,uint256 idx) internal pure returns(int256){ unchecked {
        if(idx<4)return 0;if(idx>=4+ni)return lastU;idx-=4;
        return int256(((idx<16?w0:w1)>>((idx&15)<<4))&0xffff)*int256(K64);
    } }
    // Clamped cubic B-spline at integer x: span m (coefficients m-3..m) and the 4 nonzero bases N (WAD), Cox-de Boor.
    function basis(uint256[87] memory W,uint256 base,uint256 ni,uint256 last,uint256 x,int256[4] memory N) internal pure returns(uint256 m){ unchecked {
        int256 xu=int256(x)*U;int256 lastU=int256(last)*U;uint256 w0=W[base];uint256 w1=W[base+1];
        uint256 q;uint256 hi=ni;
        while(q<hi){
            uint256 mid=(q+hi)>>1;
            if(int256(((mid<16?w0:w1)>>((mid&15)<<4))&0xffff)*int256(K64)<=xu)q=mid+1;
            else hi=mid;
        }
        m=3+q;
        int256 l1=xu-kn(w0,w1,ni,lastU,m);int256 r1=kn(w0,w1,ni,lastU,m+1)-xu;
        int256 l2=xu-kn(w0,w1,ni,lastU,m-1);int256 r2=kn(w0,w1,ni,lastU,m+2)-xu;
        int256 l3=xu-kn(w0,w1,ni,lastU,m-2);int256 r3=kn(w0,w1,ni,lastU,m+3)-xu;
        evalBasis(l1,r1,l2,r2,l3,r3,N);
    } }
    function basisPair(uint256[87] memory W,uint256 base,uint256 ni,uint256 last,uint256 x,int256[4] memory N,int256[4] memory M) internal pure returns(uint256 m){ unchecked {
        int256 xu=int256(x)*U;int256 lastU=int256(last)*U;uint256 w0=W[base];uint256 w1=W[base+1];
        uint256 q;uint256 hi=ni;
        while(q<hi){
            uint256 mid=(q+hi)>>1;
            if(int256(((mid<16?w0:w1)>>((mid&15)<<4))&0xffff)*int256(K64)<=xu)q=mid+1;
            else hi=mid;
        }
        m=3+q;
        int256 l1=xu-kn(w0,w1,ni,lastU,m);int256 r1=kn(w0,w1,ni,lastU,m+1)-xu;
        int256 l2=xu-kn(w0,w1,ni,lastU,m-1);int256 r2=kn(w0,w1,ni,lastU,m+2)-xu;
        int256 l3=xu-kn(w0,w1,ni,lastU,m-2);int256 r3=kn(w0,w1,ni,lastU,m+3)-xu;
        evalBasis(l1,r1,l2,r2,l3,r3,N);
        evalBasis(r1,l1,r2,l2,r3,l3,M);
    } }
    function evalBasis(int256 l1,int256 r1,int256 l2,int256 r2,int256 l3,int256 r3,int256[4] memory N) internal pure {unchecked {
        int256 d=r1+l1;int256 n0=r1*U/d;int256 n1=l1*U/d;int256 n2;
        int256 tmp=n0*U/(r1+l2);n0=r1*tmp/U;int256 sv=l2*tmp/U;
        tmp=n1*U/(r2+l1);n1=sv+r2*tmp/U;n2=l1*tmp/U;
        tmp=n0*U/(r1+l3);n0=r1*tmp/U;sv=l3*tmp/U;
        tmp=n1*U/(r2+l2);n1=sv+r2*tmp/U;sv=l2*tmp/U;
        tmp=n2*U/(r3+l1);n2=sv+r3*tmp/U;N[3]=l1*tmp/U;
        N[0]=n0;N[1]=n1;N[2]=n2;
    }}
    // sd axis has no interior knots: Bernstein cubics in u=k/7.
    function bern(uint256 k,int256[4] memory B) internal pure { unchecked {
        int256 a=int256(k);int256 c=7-a;
        B[0]=c*c*c*U/343;B[1]=3*a*c*c*U/343;B[2]=3*a*a*c*U/343;B[3]=a*a*a*U/343;
    } }
    // Node sums carry U^3/8 scale: divide, clamp each grid node at 0 (as the decoder), then bilinear in (f,g).
    function bl(int256 n00,int256 n10,int256 n01,int256 n11,int256 f,int256 g) internal pure returns(int256){ unchecked {
        int256 D=8*U*U;n00/=D;n10/=D;n01/=D;n11/=D;
        if(n00<0)n00=0;if(n10<0)n10=0;if(n01<0)n01=0;if(n11<0)n11=0;
        return ((n00*(U-f)+n10*f)/U*(U-g)+(n01*(U-f)+n11*f)/U*g)/U;
    } }
    struct Ctx { uint256 nr; uint256 nc; uint256 last; int256[4] B0; int256[4] B1; int256 tt; }
    // Fee surface interpolated at rows i,i+1 (weight f), columns j,j+1 (weight g), sd levels k,k+1 (weight tt).
    struct Patch {int256[4] Nr0;int256[4] Nr1;int256[4] Nc0;int256[4] Nc1;uint256 mr0;uint256 dr;uint256 mc0;uint256 dc;}
    function patches(uint256[87] memory W,Ctx memory X,uint256 i,uint256 j) internal pure returns(Patch memory P,Patch memory M){unchecked {
        P.mr0=basisPair(W,0,X.nr-4,320,i,P.Nr0,M.Nr1);
        uint256 mr1=basisPair(W,0,X.nr-4,320,i+1,P.Nr1,M.Nr0);
        P.dr=mr1-P.mr0;M.mr0=X.nr+2-mr1;M.dr=P.dr;
        // 0c column knots are asymmetric; 1c contains exact integer interior knots.
        if(X.last==12||X.nc==12){
            P.mc0=basis(W,2,X.nc-4,X.last,j,P.Nc0);P.dc=basis(W,2,X.nc-4,X.last,j+1,P.Nc1)-P.mc0;
            M.mc0=basis(W,2,X.nc-4,X.last,X.last-1-j,M.Nc0);M.dc=basis(W,2,X.nc-4,X.last,X.last-j,M.Nc1)-M.mc0;
        }else{
            P.mc0=basisPair(W,2,X.nc-4,X.last,j,P.Nc0,M.Nc1);
            uint256 mc1=basisPair(W,2,X.nc-4,X.last,j+1,P.Nc1,M.Nc0);
            P.dc=mc1-P.mc0;M.mc0=X.nc+2-mc1;M.dc=P.dc;
        }
    }}
    function interp(uint256[87] memory W,Ctx memory X,Patch memory P,int256 f,int256 g) internal pure returns(int256){ unchecked {
        int256[4] memory Nr0=P.Nr0;int256[4] memory Nr1=P.Nr1;int256[4] memory Nc0=P.Nc0;int256[4] memory Nc1=P.Nc1;
        uint256 mr0=P.mr0;uint256 dr=P.dr;uint256 mc0=P.mc0;uint256 dc=P.dc;
        int256 A0;int256 A1;int256 A2;int256 A3;int256 A4;int256 A5;int256 A6;int256 A7;
        uint256 nc=X.nc;bool two=X.tt!=0;bool point=!two&&X.B0[0]==U;
        int256 b00=X.B0[0];int256 b01=X.B0[1];int256 b02=X.B0[2];int256 b03=X.B0[3];
        int256 b10=X.B1[0];int256 b11=X.B1[1];int256 b12=X.B1[2];int256 b13=X.B1[3];
        for(uint256 bb=0;bb<=dr+3;bb++){
            int256 s0;int256 s1;int256 s2;int256 s3;
            uint256 Li=(mr0-3+bb)*nc+mc0-3;
            for(uint256 cc=0;cc<=dc+3;cc++){
                uint256 lane=W[3+(Li>>2)]>>((Li&3)<<6);Li++;
                int256 c0=int256(int16(uint16(lane)));int256 d;
                int256 wc0=cc<4?Nc0[cc]:int256(0);int256 wc1=cc>=dc?Nc1[cc-dc]:int256(0);
                if(point){d=U*c0;}
                else {
                    int256 c1=int256(int16(uint16(lane>>16)));int256 c2=int256(int16(uint16(lane>>32)));int256 c3=int256(int16(uint16(lane>>48)));
                    d=b00*c0+b01*c1+b02*c2+b03*c3;
                    if(two){int256 d1=b10*c0+b11*c1+b12*c2+b13*c3;s2+=wc0*d1;s3+=wc1*d1;}
                }
                s0+=wc0*d;s1+=wc1*d;
            }
            int256 wr0=bb<4?Nr0[bb]:int256(0);int256 wr1=bb>=dr?Nr1[bb-dr]:int256(0);
            A0+=wr0*s0;A1+=wr1*s0;A2+=wr0*s1;A3+=wr1*s1;
            if(two){A4+=wr0*s2;A5+=wr1*s2;A6+=wr0*s3;A7+=wr1*s3;}
        }
        int256 v0=bl(A0,A1,A2,A3,f,g);
        if(!two)return v0;
        return (v0*(U-X.tt)+bl(A4,A5,A6,A7,f,g)*X.tt)/U;
    } }
    function table(uint256 ph,bool sy) internal pure returns(uint256[87] memory W,uint256 nr,uint256 nc){ unchecked {
        if(ph==0){T0c(W);return(W,24,10);}
        if(ph==1){if(sy){T1s(W);return(W,24,14);}T1c(W);return(W,18,12);}
        if(sy){T2s(W);return(W,24,14);}T2c(W);return(W,12,8);
    } }
    // real.py RealPolicy.lookup: w, r, sd in WAD bps; returns (bid fee, ask fee) in WAD.
    function sdBasis(Ctx memory X,int256 sd,bool point) internal pure { unchecked {
        if(point){X.B0[0]=U;return;}
        uint256 k;while(k<6&&sd>=S(k+1))k++;
        int256 tt=(sd-S(k))*U/(S(k+1)-S(k));if(tt<0)tt=0;if(tt>U)tt=U;
        X.tt=tt;bern(k,X.B0);if(tt!=0)bern(k+1,X.B1);
    } }
    struct Grid {uint256 i;uint256 j;uint256 last;int256 f;int256 g;int256 base;}
    function grid(int256 w,int256 r,uint256 ph) internal pure returns(Grid memory Q){ unchecked {
        int256 pw=w/5+160*U;if(pw<0)pw=0;if(pw>320*U)pw=320*U;
        int256 p2;
        if(ph==0){int256 l2=r/5;if(l2< -6*U)l2=-6*U;if(l2>6*U)l2=6*U;p2=l2+6*U;Q.last=12;}else{p2=pos2(r/5);Q.last=48;}
        Q.i=uint256(pw/U);Q.j=uint256(p2/U);if(Q.i>319)Q.i=319;if(Q.j>Q.last-1)Q.j=Q.last-1;
        Q.f=pw-int256(Q.i)*U;Q.g=p2-int256(Q.j)*U;Q.base=(pw-160*U)*5;
    } }
    function offsets(int256 w,int256 r,uint256 ph,bool sy,int256 sd) internal pure returns(int256 a,int256 b){ unchecked {
        Grid memory Q=grid(w,r,ph);
        Ctx memory X;(uint256[87] memory W,uint256 nr,uint256 nc)=table(ph,sy);X.nr=nr;X.nc=nc;X.last=Q.last;sdBasis(X,sd,ph==0&&sd==0);
        (Patch memory P,Patch memory M)=patches(W,X,Q.i,Q.j);
        int256 Fa=interp(W,X,P,Q.f,Q.g);
        int256 Fb=interp(W,X,M,U-Q.f,U-Q.g);
        return(Q.base+Fa,Fb-Q.base);
    } }
    function convert(int256 a,int256 b,int256 w) internal pure returns(int256 fb,int256 fa){ unchecked {
        int256 aw=a-w;int256 bw=b+w;
        fa=aw>0?U-exp(-aw/10000):int256(0);fb=bw>0?U-exp(-bw/10000):int256(0);
        fb=clip(fb,0,U/10);fa=clip(fa,0,U/10);
    } }
    function quote(Belief memory b,int256 s,bool buy,int256 oldR,uint256 ph,bool mixed) internal pure returns(int256 fb,int256 fa){ unchecked {
        int256 ls=ln(s);int256 w=(ls-b.m)*10000;
        int256 a;int256 d;uint256 n=mixed?2:1;
        int256 lr=mixed?ln(oldR):ln(b.r);
        for(uint256 i=0;i<n;i++){
            int256 qw;int256 qr;uint256 phase;bool sy;int256 sd;
            if(mixed){
                int256 m=i==0?b.lp:b.mt;
                int256 rival=clip(lr,m+(-3004509020298721),m-(-3004509020298721));
                sy=false;phase=i;
                if(i==1){
                    int256 cand=buy?ls+ln(U-b.fb)-(-3004509020298721):ls+(-3004509020298721)-ln(U-b.fa);
                    sy=buy?cand<rival:cand>rival;if(sy)rival=cand;
                    sd=root(b.vt)*10000;
                }
                qw=(ls-m)*10000;qr=(rival-m)*10000;
            }else {qw=w;qr=(lr-b.m)*10000;phase=ph;sy=b.sy;sd=root(b.v)*10000;}
            (int256 ai,int256 bi)=offsets(qw,qr,phase,sy,sd);
            if(mixed){int256 weight=i==0?b.pi:U-b.pi;a+=mul(weight,ai);d+=mul(weight,bi);}
            else {a=ai;d=bi;}
        }
        return convert(a,d,w);
    } }
    function T0c(uint256[87] memory W) internal pure { unchecked {
        W[0]=0x2b762af92aaf2a6729f0290226fe2610259925512507248a23b422211e0711d1;
        W[1]=0x0000000000000000000000000000000000000000000000003e2f31f92ddf2c4c;
        W[2]=0x000000000000000000000000000000000000000002f002e0024800b8001b000b;
        W[3]=0x1813181b1872184717ef18cf17c618390000000000000000180018521836183e;
        W[4]=0x183218f917db18521850184518ac1880185417c919441863180c191d17aa1846;
        W[5]=0x0000000000000000144c14ad148114891849187d185a18620000000000000000;
        W[6]=0x143e17811158146514c512ff164b14cb143a158113b0147814801389158914aa;
        W[7]=0x14721595144a14a4000000000000000014a214b6152614f314591622136e141c;
        W[8]=0x0e500d880f2d0e780dd60ff00cdf0e1f00000000000000000e1e0e600e450e50;
        W[9]=0x0e560ed60e090e0e0ebd0cf810210f570eb20be6120b0ec90dde10c20c330e15;
        W[10]=0x0000000000000000074f075e074407460e9d0dbc0f040e970000000000000000;
        W[11]=0x077d0928059a072f07d20630085c078f073b07fe06d407320783068907e3076a;
        W[12]=0x077c08ee06b4073d000000000000000007a40882070a07b10767092f064e069b;
        W[13]=0x042a03e803ec03d703fe044d037903a00000000000000000041203fa03ba03ba;
        W[14]=0x047604cc053a054604db03cb062d0606044d04d904ca040d042804d9036903bd;
        W[15]=0x000000000000000002c802ed028702810492047105ba05cd0000000000000000;
        W[16]=0x03af02c30425052d03200309030c026f02c00331027802a502f202a702a6026f;
        W[17]=0x038803ee03ae0339000000000000000003a5038e041103ee032d0488032002eb;
        W[18]=0x0266025d023801d50232029c01db02540000000000000000026a024b020f0201;
        W[19]=0x033d022d048e06c7031202e90390035802c5031e037c025802b2026f02500326;
        W[20]=0x0000000000000000022e021201da01cc0305031f033f059b0000000000000000;
        W[21]=0x028e02a002f403a5028401e8026c021401fe024801c801f3027201a201ff01b5;
        W[22]=0x02d20301033a01d9000000000000000002800392032300ac02e202f702b30355;
        W[23]=0x0238018801e80195018a02b7017001ea0000000000000000022d01cb01c301b2;
        W[24]=0x03070232039f03aa025702c602ab02f802b60225033d01cc01e8025901c60294;
        W[25]=0x000000000000000001ec01c801b6019702ab02860340035d0000000000000000;
        W[26]=0x0203028702690308024a014a020c01b5019e022e017101c402ac00a0021b0178;
        W[27]=0x027902ed020303130000000000000000026d02660255033102ac0276031f026f;
        W[28]=0x0233009801de013300ff034f00660176000000000000000001d5016801660162;
        W[29]=0x026d026703a5017301d9025e016b02a202a0016902a401c201140270012b0200;
        W[30]=0x00000000000000000142010200f600fa024601ec037301bc0000000000000000;
        W[31]=0x00e302de006901ed01aefef60225009400f50236ffad01250233fdca03690205;
        W[32]=0x01a101d601a801ed0000000000000000015a0255008d029701f100fa02aa0182;
        W[33]=0x0121fe76021c017eff9404e5fad7fe17000000000000000000b9ffc80022016b;
        W[34]=0x01400044023700c4008f019c003900e70134ff34022400e2fff001e6fe96ffab;
        W[35]=0x0000000000000000000c00b8ffdffd4100f500ff011400f80000000000000000;
        W[36]=0xff960187fea6ffcf00b2fc7e02c8001effd102a8fc0e002d00eaf6730df70125;
        W[37]=0x0063005c00740084000000000000000000120121ff56008a008effaf011a0073;
        W[38]=0x005df6c704e8ffd6fe5514b4eccbff0300000000000000000010fbd9023801ea;
        W[39]=0x0089fea501250020ffb40140ff66fff90055fc9b00c3ffdfff3305d9fe12ffaf;
        W[40]=0x0000000000000000ffb2017efecafdb2000d004a000a001f0000000000000000;
        W[41]=0xffe20183ff6a00140043fd5c010cfff4ff9b0354fd6b000a00a2f92d0672000e;
        W[42]=0xffe0ffcaffd000000000000000000000ffe900cbff0d000c000bff290071ffee;
        W[43]=0x002efe7b007c0008ff8a0351fdc5ffc300000000000000000008ff64005a004d;
        W[44]=0xffddffc6005cfffefffe0062ffce00030010ff230047fffdffd70130ffa6fffb;
        W[45]=0x0000000000000000fffa0016ffebffc20001001e0014fffd0000000000000000;
        W[46]=0x00000038ffe800020006ffb0001ffffefff4004fffda00010010ff5e005ffffb;
        W[47]=0x0005ffc5fff400010000000000000000001dffcaffcf0002fffbffe50012fffe;
        W[48]=0x0002ffe100090000fffd0037ffe900000000000000000000fffffffe00020001;
        W[49]=0xffe10028000f000000040006fff90000fffeffe6000affffffff001efff60000;
        W[50]=0x000000000000000000000001ffff0000fffb00160004ffff0000000000000000;
        W[51]=0x0004000efff90000fffcfff0000700000002000efffa0000fffcffe9000b0000;
        W[52]=0x0005ffd2fffe000000000000000000000018ffaafff20000fffafffd00050000;
        W[53]=0xffffffea0008000000030024fff2000000000000000000000000ffff00010000;
        W[54]=0xffda003d002900000004fffefff70000fffeffe5000c00000001001bfff50000;
        W[55]=0x000000000000000000000001ffff0000fff8002c000700000000000000000000;
        W[56]=0x00000025ffea00000001ffda00120000ffff001afff300000001ffd500160000;
        W[57]=0x0008ff96ffe60000000000000000000000170009ff4f0000fffdfff300160000;
        W[58]=0x0001ffee00090000ffff001dfff1000000000000000000000000ffff00010000;
        W[59]=0xfff4ffe7006e00000001000cffec00000001ffe500110000ffff0019fff30000;
        W[60]=0x00000000000000000000000000000000fff7003c0013ffff0000000000000000;
        W[61]=0x00000008fffa00000001fff800040000ffff0005fffd00000001fff800050000;
        W[62]=0x0001ffd3fffa0000000000000000000000010014ffc40000fffffffb00050000;
    } }
    function T1s(uint256[87] memory W) internal pure { unchecked {
        W[0]=0x2a892a072989291128a0283427cc276026ef267725f9257724df23f420d812c5;
        W[1]=0x0000000000000000000000000000000000000000000000003d3b2f282c0c2b21;
        W[2]=0x000000000000000000000000091007a906f6068d063005d00573050a045702f0;
        W[3]=0x17d8189617bc18221739180117d6180a16ed186b17d91806173b181917fb1806;
        W[4]=0x1841176019be186217c318c217e6180f17d018f91765182c17cd18371856182c;
        W[5]=0x181b18b917a517de181418c517b61893182c179a193f1875182f17171a31184e;
        W[6]=0x131a150f13a114351349140e142e141b185218bc17c1182b185d1875182d1809;
        W[7]=0x148d12be161214721404147513c8142c1405139314e7146113571439149d141b;
        W[8]=0x13f515fd12b2124313df173a10131345136517ce0f0c13b414a9139c148714c9;
        W[9]=0x1481145715ad14b0145a158713bb15bf145d140f155b1565144f13fc14ed1396;
        W[10]=0x0d3e0e610c400d3c0c620dfd0c5a0d6d0c710c910dcd0d320c810dcf0d030d5b;
        W[11]=0x0eae086515670e300c490f810c600cdd0cae0f8b0b3c0d440d000dcf0ddd0d91;
        W[12]=0x0d6e0e7f0be80c020d660ee40c430f150dec0ad6112f0fe70dc00a4313220f14;
        W[13]=0x05f4066105e805ff058f05e105c605f00db00ed20a900d020dfd0cba0df30abb;
        W[14]=0x06e3053807240636064405ff05a905ff0610059706f506240558059805e905df;
        W[15]=0x0646085c033e049e0646086402e6050f05a2094e019905b7074604d306ef0683;
        W[16]=0x06e8069b08f4079806ad081c06d2098a06d00601074e06b406a60633060304be;
        W[17]=0x028f0269022b0260034602de0284028102610252021802450290020f02930262;
        W[18]=0x03a5028a04a002da028004a601f8024902a603c4022c02870310034002a8029f;
        W[19]=0x038e0450047e04ae03750453046204ca0394035204d4043c0363035e044b0398;
        W[20]=0x014b00a5015401830169018effbc01350417049b04990477042d04e5049b042a;
        W[21]=0x0257023a025d01e601fc022d01d501c5021101d801b701bb0256022001d30193;
        W[22]=0x02c4031702e4031402b102bb02ca0331027802b6026e032a02c901c402f40319;
        W[23]=0x03bc03b50379039203c703c103bd03ec031e03a4032b033d031003140378030c;
        W[24]=0x01ee019b018b01a501b101ac01e2011d017d01ebffde01430165ffcf02e700f1;
        W[25]=0x024002220298022b022b01dd024b020e01f801fb01b1023801d201c101bf0198;
        W[26]=0x02c703490306032d02af02fd02f8032b027e028b02eb02c7025c024302ce0279;
        W[27]=0x00fa00a90052ffe000c50021ffff0194038a037b0387034203ae035b0390033d;
        W[28]=0x01d8019301cd01aa01b3017a017b018401b101810147010301d7016501280186;
        W[29]=0x0242025802730276022a0203024b025601fb01e10216024201e901bc01e50212;
        W[30]=0x0385034e0276031403a303460311033f02bd02ee02b602b20291029102bf0295;
        W[31]=0x019f010e012f00f90116012500ff00d80113011a000d002000b3ff38ff850112;
        W[32]=0x01c501c501e801d201c5016101cb0196017e0184013d01ae0176012e012d013d;
        W[33]=0x029c02b9027e0293024c02790267026e020d021f0237023201db01f5020601f4;
        W[34]=0x006a00caff3dfff60066fe3403be0044039302d103e502b4038c030e02e202b6;
        W[35]=0x015c01040144012f015700c7012d00f6013d012200af00e10150008600fd0087;
        W[36]=0x01d501dd01f901e101a101bd01b901c701a3015001b301910154016901320190;
        W[37]=0x03a2035c00df029403af033b02a903190282024c026b02020211027e01fd0230;
        W[38]=0x011e0084012d004800ba0114ff4b00d3002effdf0233feb200080479ee7800d2;
        W[39]=0x013f014301450158014300eb0138012700fc00ef00e3010a011800d1006e010e;
        W[40]=0x021502ef01ac024701d901f3024701bd017a01e3017501b80175015b01ae0164;
        W[41]=0x000702c8fb4cffd80020f7aa0ba9fe3903d4034d05c201b103fe025a02e20247;
        W[42]=0x00fc005e00de008300e7007a0079013a00e200e5ffb200a100cdff4501faffca;
        W[43]=0x0155014201a90161013c0131014e0141011800da012000fc00e200e600d20106;
        W[44]=0x03e5061105a80a39042504f701ad023501a3019a028d021e01bc0215017401a3;
        W[45]=0x0051005e00290124010f00c3ff58fdbbff40fcaf025e032aff58057af7c1fb4b;
        W[46]=0x00ce00c500d400c600cf006b00ba00e20083008b0054008500de0052002400b4;
        W[47]=0x01b80233018300ca0164015f01b901bd011b014f014600e400f600ee00fb0120;
        W[48]=0x0099fad90478fd14ff6400eeff4502650468072203a0073a0418019d04460686;
        W[49]=0x008b000ffff500c0008a0019005300b400d5ff57ffc900d8ffdc0198fe7300ac;
        W[50]=0x00e400ec012a009200ce0083010600e600900093006d0081007f002c00bb0015;
        W[51]=0x047e03330a8e044603f2007d056f068d01af01ee0128008001310147013601a9;
        W[52]=0x0024ffd9ffe3006300d8fbf1020d007dfde208bbfaebff95007cfcf2011afefd;
        W[53]=0x006b0021008f007d0046fffd002d0058004d0040ffe700310088fef200fe004f;
        W[54]=0x014300d801c0ffe500ed013200f9018e00ae00bb00c800700066008d0041006f;
        W[55]=0x015bf8220412000bff60025dff0afed7040e0775085e051d0311052a016306e9;
        W[56]=0x0091fd99010a004bffd1009cff90003e0043fdce0158003dff510426fd850042;
        W[57]=0x0062007200740068005afffa00b40052001f0002fff8fff0fff5ffd8ffe3ffc7;
        W[58]=0x03e5061e0831030702fb016702ff05f30152014d0125004b00aa00c600c700e3;
        W[59]=0xffc50114ff49002c00b4fd57017effd8fecd0471fdcbffdf0043fe6d0080002a;
        W[60]=0xff8afff60029ffee00110002ff78001fff580171ff85ffea002eff4a0076ffe6;
        W[61]=0x0032019affceff42009b003a00e600f70020006b00120010ffbeffccffa7ffc6;
        W[62]=0x006bfda50136fffdffd00091ffb0fff2030e089f093703be044401190457070e;
        W[63]=0x002dff3d0012fffcfff2005affc0000c0013ff6a0065ffd7ff990167ff2a0018;
        W[64]=0xffbcffa1ffbaffca0055ff82007a0015ffd900a9ff89fff7001dffb9006cfff3;
        W[65]=0x030102c90d0100d1027e014501b804ff00c2ffff0128fff0002d009d00200033;
        W[66]=0xfffa001bffe700050016ffae003cffffffde0089ff9dfff70007ffd800120003;
        W[67]=0x002eff21003bfff6ffe0004fffd70007ffe60022fffafff90006fff00012ffff;
        W[68]=0xff790098ffb3ff570000ffb0ffb60010ffd3ffdb0065fff6ffa600b1ffa90002;
        W[69]=0x000dffcbffe8fff9fffa000cfffc0002029e0375140e02f403c002f20279058c;
        W[70]=0x0010ffdcffb8fff6fff7000d000a00060006fff2ffecfff7ffee0027000d0008;
        W[71]=0xffebfe7afeceffc80006ffdb00ce0019000c0068fec9ffe5fffbffe30062000a;
        W[72]=0x01d5fd0304df0112018705cd031602dcfed3faf4fe77fecd00a8020a0146005e;
        W[73]=0x0003ffed000500090002fffa0009fff6fffc0014fffb00080002fff90004fffc;
        W[74]=0x00b7fd3b00780021ff7b0121ffc4fff0000dffae001a000cfff5001a000afff8;
        W[75]=0x022bfd8200bafd77fba7086cff94ff9a013ffb720107003efe9402bdff6fffd7;
        W[76]=0x0004ffe20024fff7fffe000afff20003fe3601df019cfc26fe2cfdfffaa30046;
        W[77]=0xfff1004c006dffee0008fffeff850009fffc000a0025fff2fffd0015ffbf000c;
        W[78]=0xfe5506300445ffa10130fdd0fb850032ff3202db023affcc0078fef4fe5f0013;
        W[79]=0x00fdfc2e00a5010e021004e8fe7201e1fceb01b317e503bb03fff3e1eddd0070;
        W[80]=0x0003fff9ffdc00080001fff50030fff9fffe0010ffe300050001fffb0009fffe;
        W[81]=0x008afe3afca50019ffa400aa0172fff6000cffccff6e0009fffa00030056fffb;
        W[82]=0x025c029fdd65fb5bfd2f05641178ffe70122fca6f7c30029ff22013904a9ffe7;
        W[83]=0x0001fff9000cfffeffff0002fffc0000ff860199ffce0008fe63fb0a01c8fcd8;
        W[84]=0xfffc000e0028fffd00010001ffd30002ffff0000000ffffcffff0006ffea0003;
        W[85]=0xffab01540169ffed0021ff9dfe2d0007ffd9008400c4fff6000fffb6ff600003;
        W[86]=0x000fffa20006ffe7002d009effe1009aff7d009f065e00660074fd27f94a0011;
    } }
    function T1c(uint256[87] memory W) internal pure { unchecked {
        W[0]=0x0000000037dd2d9b2af42a2d298e28f7285527ab2709267225d3250c22651823;
        W[2]=0x000000000000000000000000000000000781074006bc064505bb054404c0047f;
        W[3]=0x17da180c18131828179c1808183f181e172018b817cf183617631852180e1826;
        W[4]=0x18a614971b5b185d1855182718161843180717731927182917b0185e1807182c;
        W[5]=0x17e618e917c9185c185b168319b217e1174a1b82163618aa18a7163a18d3184e;
        W[6]=0x12f913f0131d1327128c135912d5131a1245131b133513281275137812f41328;
        W[7]=0x119d19ad0e6d129611ac16c10f5a12e0127a17640ec1134413a5128a14101339;
        W[8]=0x1336127e13bd12f21202186c0f1c13a514ce0c561768129c113e1887119112cb;
        W[9]=0x0b960b900be20bfc0b950af30c9b0bee0ae40d7b0b190c1b0b3c0bec0c010bf4;
        W[10]=0x0d8407240fad0cdc0dad07c410470c780c4209690f220be20aaf0c5f0b980bf2;
        W[11]=0x0bb60d7c0b1c0c930d0506ee11a60b7a09fc13c105f30d330dd108000e170c9c;
        W[12]=0x051004910484047a03f1059d03f7045b048b039c04c00481046504be04510473;
        W[13]=0x046206fa02f903f1041b07160269043b04b405c0037404a205b40481048c0487;
        W[14]=0x050d04d8048a041404d9071c015204f2055602e506f7039004b20641035b0418;
        W[15]=0x0210029801cf01e202170095021b01a902fa034a01450264025d01c7020701a8;
        W[16]=0x02ea027a041b0399030d01e8043f0282025602d102a501c201c602f101e801ee;
        W[17]=0x02ba034c03eb047c035b011806c50233024304cd021e05fe02e902b1045a0406;
        W[18]=0x01df017701a0019901f30216015c00d501d10098040b020401da01f8008b0148;
        W[19]=0x023d021502f2012b01e602c8005f04fa01c4025a00b80438020b017a01f4016c;
        W[20]=0x027f026d02bf01ed021d0353005903e802c801f6043b00c702480260029101f7;
        W[21]=0x01a9012a014900f001a7014000e601e6019dffbc0202005101ad01c000e0016c;
        W[22]=0x01e6020201f8029f01dc018202850127020700cc02efff8a016f0177011c01d5;
        W[23]=0x02160275026102bc0281012903a401a601d703700180037b020d0213025b027a;
        W[24]=0x015400ea00cf0168015101ca00f6fde101bcfebf01140388012e01be0107fffb;
        W[25]=0x01b8016e0265010401670190015501900156016200730350013a00e101500031;
        W[26]=0x021501f3020701d900d3032a00d701c602f20143031c01e80191020101c601c6;
        W[27]=0x011100c40060009c00d8ff9101e6024600f7042efd38ffdb0129ff7600ee015b;
        W[28]=0x011b01a0011a0196015000db013a01a700e200db0148ffc60141002d00e20135;
        W[29]=0x016b01e3020701870215012700aa0209011f027c020601730177013c01eb0139;
        W[30]=0x00a2007b002900af01b3ff7fff2f016e0006fee5038f000d00ed009aff7600e5;
        W[31]=0x011000a001b2006600be00d10085010900bd003a00b100d700c80030004e002d;
        W[32]=0x01800144013b01340047020a0160013a025300ad023b010b00e5016000f7016f;
        W[33]=0x008d0008ffde0125ff910142fdd2ff56015dff5e012f012d0051ffd0ffe4003d;
        W[34]=0x007b00e2002201060095001600d000560065fff80083ff930087ffefffbe011e;
        W[35]=0x00d600fe00eb012c016500c0014800020093020a001f01fa00c100b101090093;
        W[36]=0x0003ffcdfeee016e00e7fdeb04a7ffa0ff92ff1bfd850073004eff4101160040;
        W[37]=0x007fffd2011cffc4fff10042ffc4002f0039ff2e004effbc005aff61001000b7;
        W[38]=0x00d7004800e700aa002c0215ff8b00990130007c01ae00ca0062007c006300ba;
        W[39]=0x0013ffdc006aff90ff560154fe22ff040069ff5f012100ceffd20042ff98ffaf;
        W[40]=0xfff4ffccff3c0019fff6ffc40010ffee00020037ffb0002affcd003bffedffc8;
        W[41]=0x008d0038ff400079ffe500ce02c0ff0900f60066ff6e00deffcf0074001dffe3;
        W[42]=0xfff7fff80005ffff0047ffa600620006ffba0045ffadfff1000effed00150000;
        W[43]=0xff5000df0034fff10047fff5ffbd0008ffd100060035fff3002affd4ffec0006;
        W[44]=0xffa70067006bffc700a6fd2cfe2b004cfed00331ff9fffad0086fdaf0039000a;
        W[45]=0x000e0009fff60000ffa10067ff92ffff0048ffb600560004ffe9001affe50000;
        W[46]=0x010cfd8fffe10009ff66002d0050fffa0054ffe9ffc10006ffb7004a0008fffd;
        W[47]=0x0038fe8dfff50018fedc05fdffc5ffca0182f7b701360035ff1003c2ffa1fff9;
        W[48]=0xffddffd90022ffff0069ffcb00570001ffac0031ffacfffb0013ffef0017ffff;
        W[49]=0xfdb2044400c9ffef00fa001cfef9000aff4500330091fff5008bff17ffed0005;
        W[50]=0xff9c01a0fffeffdc01a1f64f0068005cfd830e01fe79ff97019bf5c6008a000d;
        W[51]=0x0010004cffba0001ffc1ffedffee00000031ffff00230002fff30005fff40000;
        W[52]=0x017dfcf7fe15000cff53fecd018cfff800710059ff090007ff8b0090003bfffc;
        W[53]=0x0039fedefffe0016fed50650ffbfffbc01d9f68800b20048fe76073d0013fff6;
        W[54]=0xfffaffd400170000000d001cfffdfffffff4fff3fffa00000001000000020000;
        W[55]=0xff5b01770059fffc002fffbcff9b0002ffd80036001efffd0017ff8500000001;
        W[56]=0xffe4004afff5fff80056fd3e0032000fff700411ffeaffed004efc34ff4c0002;
    } }
    function T2s(uint256[87] memory W) internal pure { unchecked {
        W[0]=0x2a992a092989291328a2283627ca275e26ed267725f7256724b42395204c12b7;
        W[1]=0x0000000000000000000000000000000000000000000000003d492fb42c6b2b4c;
        W[2]=0x000000000000000000000000094507e30720069d063305cd056304e0041d02bb;
        W[3]=0x17bb187d17b4180d172818051806180f1704187817c91803172f182817f51807;
        W[4]=0x17a4196a170a17f717b918be176f182b17dc1844181b181f17a5184618281821;
        W[5]=0x17cd196f1686196717f717f1193f183e17e0183e18f4183e17d7181818db1828;
        W[6]=0x133214c813e014361358141414201426180618a117ec1870182217ea19301795;
        W[7]=0x13f1148913f7143713f1146c13b4143013f2139315011457130f145e13f9141a;
        W[8]=0x14211496121f13a5141c151212231423149a11f8164f1515143b134e15cc1429;
        W[9]=0x1442144c144413ee140a1591122c151a14761245172311de13f0159c112213c7;
        W[10]=0x0d510e2b0c4b0d5f0c7a0e5d0d330d790cbd0cc80d9f0d660ca00e1a0d230d6e;
        W[11]=0x0c69118d09f80c8c0cdd0fa10b060d930d7c0d540dbf0d9d0ce10dfa0e020d8b;
        W[12]=0x0cf010d20a9a10000dae0c3912260ed20d420db011030e410d330d2d10760da2;
        W[13]=0x05e906da05ea062c05af05c5062b062a0d880e400ddc0e110dd80cf90f800dd4;
        W[14]=0x064b0694060e062f068d05f20601063606040629069e0644059c057d06360617;
        W[15]=0x06e105f5045a05cb06c7069604830658076203c0088206e706d00569079d0640;
        W[16]=0x06e1068105b605b50688081103cc0608073e03f7083804430665082701e40563;
        W[17]=0x02cb02b402780297032702f8029c02a602d702980275028a02c2023d02a1028b;
        W[18]=0x02ee05680136022f0306045501be02c2034b032a02c502cc0318035b02ba02b5;
        W[19]=0x02a206d303a50515040601c0059a0390030c050b03a70321036f03c90361028f;
        W[20]=0x01980134012b01820183006700fd017603a004d8054a0543046502140673051f;
        W[21]=0x021d02ee01a401b6020f021701d401d2022801e401b701bc0261020d01d901b8;
        W[22]=0x02fb02a3039f03d90261034102f503b3032b0140044f030a020e02d1029901b1;
        W[23]=0x035d037c03530302031e04dc02df03420353029e03b2035f027c0457032a03ce;
        W[24]=0x01f4019f01a1018501b001a101c0016f014201e2009100dc01ac01590192017e;
        W[25]=0x01f602d001d40276028e014e025e02e0020501c10206019e01d201c101a9019f;
        W[26]=0x026003be02c1031302b10289032d02d1026702d202db028a028701fc02fd0253;
        W[27]=0x0171017eff53004b00f5ff0301a4012602fa036f034503820365026204350381;
        W[28]=0x01bc01bf017001e901b301670179014601b701750139010d01bd014c01450142;
        W[29]=0x023f026b027602b50219021f025b027a020e019f026b022301ea019e021301ab;
        W[30]=0x030302f802b7029c03000364029f02d4029702b002bb02ad025e02d802ab02cd;
        W[31]=0x017d0123012b00e5015500c000eb00f3008d01d800be0007011c0074ff3800b3;
        W[32]=0x01b301da01d601df01c80160019f01d3017b015a0157016d019400fb013700ff;
        W[33]=0x0266029502a1026502510279024a0256020a0213026c022301e601e6020501f5;
        W[34]=0x0110012dff52ff570086feda01e200c002f7029802f40293030e0307026f02ff;
        W[35]=0x015300f901240142014500e700e500f8014800f700c2009b011c00af00cc00e7;
        W[36]=0x01de021401d30207019c01e201c901cf01aa013201c90191015c0153014c0159;
        W[37]=0x02ea02b70216025d02fa02d602b70211027f02610207023a020002770226022a;
        W[38]=0x00dc00dd009f009a0158000300590029ff8d015900fefff300f00056fb34ff66;
        W[39]=0x0146013901540157013700f0012c013d010200dd00be00f9013f007b00e0008c;
        W[40]=0x02340225022b01c901c4027201ea01d9017601c401d601a6016e0183018f017e;
        W[41]=0x0148ff420045fd81fff0fef100e000dc0334024a0292020e0303031e0253030f;
        W[42]=0x010e002800f900a900b00113ffae01200129ffef00ceffd40031012fff790125;
        W[43]=0x013b01c8015201860144011f0187013c011c00dc011e011200e300e000c700e7;
        W[44]=0x028902db01cd01be04260331018900e7011f02d701c1027c0203015c02320193;
        W[45]=0xffcd017dfeec008701f7fd9e02c0fe86fe1d03abfad302430112fdb00297fe0c;
        W[46]=0x00d000c400de00c700d0005200c800cf00810092001700740104ffda007f00d0;
        W[47]=0x023501b1013a0117013001db017501c6013401340180011800fb00ff00fb0111;
        W[48]=0x01a1f6720aaafdb1fe7204d0f9a10133033a048d0819092201c101d7053704b3;
        W[49]=0x0090fffd000900b800cfffdf000c00ac00cbff25003400dfff5f0383faff009b;
        W[50]=0x00ce0128010300f800d50093011200d400980081007a00a50087002100a30029;
        W[51]=0x020d051d079702190556fc760562066f011b02b8013b00bd015f01320157016e;
        W[52]=0x009cfed30002003c002efde302ec0073ff25069bf7d100970088fca50412fea3;
        W[53]=0x006c0029008000720044fff100350043007effd1ffec00340059fedd00ff0054;
        W[54]=0x01b800100276000500c7018a00b9017c00cb00ac010a00a200730093005f004e;
        W[55]=0x00b3f944042effeeff7c027bfd9a00a4033305d906c3037600a20759fdb206f5;
        W[56]=0x0074fe0e00d10066ffd000d0ff9d001e0053fe4d0104007effc40246fe69ffea;
        W[57]=0x0067008900830075004b0031008800710025ffd80026fffafff9ffeeffd1ffd5;
        W[58]=0x0293032c047a05ca03defdb004400604012201f200c2004600c000ca00d30108;
        W[59]=0xfff800c0ffc4ffb6ffcdfeb30061008dff9403d4fe4afef70027fe000129ffcf;
        W[60]=0xffc20019fff1ffebffcbffe1ff69001bffb30126ffcdffd00010ff3d00280018;
        W[61]=0x006601410037ff620091007e00a801200032005a00690030fff6ffd6ffa1ffbf;
        W[62]=0xfffffe7700de0047ffee006fffadfff10239091f0852022f029200e9042006f5;
        W[63]=0x0021ff570032000bfffb0053ffcdfff9fffcff9f003f0010001a009fff93ffd2;
        W[64]=0xffd5fff0ff9effc8ffb9ff620020001000370052003400030002ffdd001ffff7;
        W[65]=0x028fff2b04ce013702fbff8c020b057800bc00cd00a7fff50032004e004c0031;
        W[66]=0xfff70029ffcafff5fffdffc800520013fff3007fff61ffe00003ffdd00180003;
        W[67]=0xff9aff54ff84ffea001800250016000affd10046ffbbfff2000affdf00260006;
        W[68]=0xff8e0072ff19ff15ffddffd5fff9001cffd7ffcc002fffea005d00a00007000c;
        W[69]=0x0006ffc800190006fffd000dfff6ffff01dd08fd0ee501fe0348011f052a0632;
        W[70]=0x0024ffb6fff4fffcfff20022fff700010007ffd9000a0000fff9002bffeffffc;
        W[71]=0xffaafe73fee2ffc9ff81fff50084001800530031ff8effeaffd9fffd002c0005;
        W[72]=0x01a1ff0a02df0051005702f801eb0279ff19fd39ff0ffedd00cb011500b8005c;
        W[73]=0xfffa000dfff7ffff0004ffef000f0005fffc0019ffeffff90001fff700070001;
        W[74]=0xffb4fe81005a000a000300a7ffb9fffeffe3ffff000200010007fff9000c0000;
        W[75]=0x00ff03f90024fedafef0ff9bfe5dffeaff43ff1b01c8001c007301a8ff3fffef;
        W[76]=0x0002ffed0019000affff0007fff7fffdfe150460ffbcfed7ffbcfb37fdb3ff3f;
        W[77]=0x00080039003f0005fffefff2ffc3fffc0002fffe00180004ffff0004ffdffff7;
        W[78]=0xffd0047fff2e0020ffe8fc28fdcfffdfffec02ce00db000c0019fe91ff7fffee;
        W[79]=0x00d6faf0012d00030156056ffec90128fd7dfd4d0c1203d5017dfdebfafafee4;
        W[80]=0x0000fff9ffeafffc000000050017000800000004fff0fff80000fffd00050002;
        W[81]=0x0025fda3fe65ffdeffe30113009600140001ffb6ffaefff6ffff0013002c0005;
        W[82]=0x01eafff3ec85fadcfecd02a506b6012c005ffb78fdedffb9ffdb030c0265002b;
        W[83]=0x0000ffff0005000200000001fffeffffffb9019affc50025fea3fd6e0175fe7a;
        W[84]=0xfffd001b001100010001fff3ffeffffeffff0004000600010001fffcfff9fffd;
        W[85]=0xffbf0187001c000e001bfe71ff3cfff1ffe600ca00470006000aff71ffd2fffa;
        W[86]=0xfff5ffc20001fff3006a007fffe3004eff2d00ac031700ad0056feeefdb4ffa7;
    } }
    function T2c(uint256[87] memory W) internal pure { unchecked {
        W[0]=0x00000000000000000000000000000000314e2bc82a0228c4273c25fe24381eb2;
        W[2]=0x00000000000000000000000000000000000000000000000007710685057b048f;
        W[3]=0x180b17571da2181b18211669159b182016911a8818541808176717b8180b1828;
        W[4]=0x17e1185a15eb180b17b518161fe3183a17681b230e2a180a19d9120a16bc1842;
        W[5]=0x112b0fd90c0111cf0fea176c13f8119e12160c3012b711b210d813d810d911c9;
        W[6]=0x114513c814691238125c0d1c0722118f121a10f822cd121f0bcb23f50f0b1161;
        W[7]=0x0b6409120cca0a2109ba0b24093c0a3b08b80c3307990a60094409630b3e0a1d;
        W[8]=0x09e00a4d08b309bf0a9b0a730fb70a44086c0f9cfc1209f80e6601120d050aab;
        W[9]=0x029d03e901f502b202f6016b02a8026702a001e8046e02950314034401a40292;
        W[10]=0x03b5029302d102d602280547014e031f0474ff8208e502bd027e05d80138025d;
        W[11]=0x01d301a801ea00f501ae011e014d01f7039602b8ff93fc77012400d002480357;
        W[12]=0x016c051f039b058904a9fae8064cfc82010b06d3fde7092a02a100a804630289;
        W[13]=0x00c70196ff6904220210ff50019afba3febe05ff07b806a60212ff34fd4bfea0;
        W[14]=0x0261fe10033c0025ffec0b95fb03047a0275004204eeff440134021400cf0111;
        W[15]=0x00ceff230120fe7f002b018dfebd02b800c0f659fe67fe0700c102d200ea01b7;
        W[16]=0x00be04a4013e01f201e3f9c1028effcf010102a50073031900d9001f01a50078;
        W[17]=0xffd9ff8300110013ffd2fffbff9a0028004cff920340003bff7bff29fedcff89;
        W[18]=0x0068fe9e017fff9500040371fbfa00ee00af00fe01eeffb3ff9f0015fecbfffe;
        W[19]=0x004c0022ffbefffaffd4003c009bffea0036fde1fd87000fffe000470068fffa;
        W[20]=0xff99fdd4ff3f001b004d06060165ff6ffe92f7f0003f001affeb00ac007cfffc;
        W[21]=0xfdd7fed2012c0008015600c3fdcb0019ff0d00a80437fff60018ffe8fed0ffff;
        W[22]=0xff9e049500beffaa0192e88ffe550104fedb160a009fffc7005ffcf0fdf10006;
        W[23]=0x0194057afd1bfff6ff42fc2a039bffeb006101b0fb5f0009fff7ffa800f90002;
        W[24]=0x003dfb8fff24003bfee610d4046fff1600cfee1cfb4b002fff2901c70382fffb;
        W[25]=0xff24f9c902090002003a03e2fe230000fff2fde40180fff6fff10058ff6bffff;
        W[26]=0xffd3005e0074ffec006cfc70fc6c0020ff88017a0463fff6fffc00f8fc56ffff;
    } }
    // Four words: arb point/weight, retail mean/variance, spots, fees/time/count.
    function save(Belief memory b) internal { unchecked {
        slots[0]=uint256(uint128(int128(b.lp)))|(uint256(b.pi)<<128);
        slots[1]=uint256(uint128(int128(b.mt)))|(uint256(b.vt)<<128);
        slots[2]=uint256(b.sp)|(uint256(b.r)<<128);
        slots[3]=uint256(b.fb)|(uint256(b.fa)<<64)|(b.t<<128)|(b.cnt<<192)|(b.sy?uint256(1)<<255:0);
    } }
    function moments(int256 p,int256 m0,int256 v0,int256 m1,int256 v1) internal pure returns(int256 m,int256 v){ unchecked {
        m=mul(p,m0)+mul(U-p,m1);
        v=mul(p,v0+mul(m0-m,m0-m))+mul(U-p,v1+mul(m1-m,m1-m));
        if(v<0)v=0;
    } }
    function afterInitialize(uint256 x,uint256 y) external override returns(uint256,uint256){ unchecked {
        Belief memory b; b.sp=int256(y*1e18/x);b.r=b.sp;b.lp=ln(b.sp);b.pi=U;
        b.fb=2823606104386589;b.fa=2823606104386589;save(b);return(uint256(b.fb),uint256(b.fa));
    } }
    struct Mix {int256 p; int256 m0; int256 v0; int256 m1; int256 v1;}
    // Reweight by the no-arbitrage likelihood, preserving both components for two cuts.
    function cut(Mix memory c,int256 lo,int256 hi) internal pure { unchecked {
        int256 z0;int256 z1;
        (z0,c.m0,c.v0)=trunc(c.m0,c.v0+893025000000,lo,hi);
        if(c.p==U)return;
        (z1,c.m1,c.v1)=trunc(c.m1,c.v1+893025000000,lo,hi);
        int256 w0=mul(c.p,z0);int256 w1=mul(U-c.p,z1);int256 total=w0+w1;
        if(total>0){c.p=divi(w0,total);}
        else {if(c.p<U/2){c.m0=c.m1;c.v0=c.v1;}c.p=U;}
        if(c.p==0){c.m0=c.m1;c.v0=c.v1;c.p=U;}
    } }
    function update(Belief memory b,int256 s,bool buy,uint256 dt) internal pure returns(bool arb){ unchecked {
        int256 lo=ln(mul(b.sp,U-b.fb));int256 hi=ln(divi(b.sp,U-b.fa));
        Mix memory c=Mix(b.pi,b.lp,0,b.mt,b.vt);
        if(c.p==0){c.p=U;c.m0=c.m1;c.v0=c.v1;}
        uint256 n=dt-1;if(n>12)n=12;
        for(uint256 i=0;i<n;i++){
            if(i==2&&c.p<U){(c.m0,c.v0)=moments(c.p,c.m0,c.v0,c.m1,c.v1);c.p=U;}
            cut(c,lo,hi);
        }
        c.v0+=893025000000;c.v1+=893025000000;
        int256 lp=ln(buy?mul(s,U-b.fb):divi(s,U-b.fa));
        int256 sd=root(c.v0);int256 la=mul(c.p,divi(pdf(divi(lp-c.m0,sd)),sd));
        int256 z0;int256 z1;
        (z0,c.m0,c.v0)=truncSD(c.m0,c.v0,lo,hi,sd);
        if(c.p<U){
            sd=root(c.v1);la+=mul(U-c.p,divi(pdf(divi(lp-c.m1,sd)),sd));
            (z1,c.m1,c.v1)=truncSD(c.m1,c.v1,lo,hi,sd);
        }
        int256 w0=mul(c.p,z0);int256 w1=mul(U-c.p,z1);int256 Z=w0+w1;
        int256 mt;int256 vt;
        if(c.p==U){mt=c.m0;vt=c.v0;}
        else if(Z>0){(mt,vt)=moments(divi(w0,Z),c.m0,c.v0,c.m1,c.v1);}
        else if(c.p>=U/2){mt=c.m0;vt=c.v0;}else{mt=c.m1;vt=c.v1;}
        int256 d=ab(ln(divi(s,b.sp)));if(d<1e9)d=1e9;
        int256 pi=pdf(divi(ln(d)+6801595083153746944,1176000000000000000));
        int256 lr=divi(mul(mul(Z,260000000000000000),pi),mul(d,1176000000000000000));
        pi=la+lr>0?divi(la,la+lr):int256(0);arb=pi>U/2;
        if(pi>5e15&&pi<995e15){
            b.pi=pi;b.lp=lp;b.mt=mt;b.vt=vt;
            (b.m,b.v)=moments(pi,lp,0,mt,vt);
        }else {
            b.pi=U;b.lp=arb?lp:mt;b.mt=0;b.vt=0;
            // Single retail Gaussian is represented by weight zero on the point.
            if(!arb){b.pi=0;b.mt=mt;b.vt=vt;b.m=mt;b.v=vt;}
            else {b.m=lp;b.v=0;}
        }
        int256 pe=exp(b.m);b.r=clip(b.r,mul(pe,997e15),divi(pe,997e15));b.cnt=0;b.sy=false;
    } }
    function afterSwap(TradeInfo calldata t) external override returns(uint256,uint256){ unchecked {
        uint256 p0=slots[0];uint256 p1=slots[1];uint256 p2=slots[2];uint256 p3=slots[3];
        Belief memory b;
        b.lp=int256(int128(uint128(p0)));b.pi=int256(p0>>128);
        b.mt=int256(int128(uint128(p1)));b.vt=int256(p1>>128);
        b.sp=int256(uint256(uint128(p2)));b.r=int256(p2>>128);
        b.fb=int256(uint256(uint64(p3)));b.fa=int256(uint256(uint64(p3>>64)));
        b.t=uint64(p3>>128);b.cnt=(p3>>192)&((uint256(1)<<63)-1);b.sy=p3>>255==1;
        int256 s=int256(t.reserveY*1e18/t.reserveX);bool arb;
        int256 oldR=b.r;uint256 dt=t.timestamp-b.t;
        if(dt>0)arb=update(b,s,t.isBuy,dt);
        else (b.m,b.v)=moments(b.pi,b.lp,0,b.mt,b.vt);
        uint256 ph;
        if(!arb){
            int256 c=t.isBuy?divi(mul(s,U-b.fb),997e15):divi(mul(s,997e15),U-b.fa);
            if(t.isBuy?c<b.r:c>b.r){b.r=c;b.sy=true;}
            b.cnt++;ph=b.cnt==1?1:2;
        }
        (b.fb,b.fa)=quote(b,s,t.isBuy,oldR,ph,dt>0&&dt<=GATE&&b.pi>5e15&&b.pi<995e15);
        b.sp=s;b.t=t.timestamp;save(b);
        return(uint256(b.fb),uint256(b.fa));
    } }
}
