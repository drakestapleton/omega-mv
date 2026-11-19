# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# real2: device-stepped Omega decode, graph replay and per-launch comparison.
import os, sys, json, time, lzma, base64, ctypes, hashlib, subprocess, urllib.request, statistics
from pathlib import Path
OBJ = {'argmax_final': ['432ab23b5cbe13bec5ff4e79c960407e3e1bf44432a53d1e0707da7bbac3e02d', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0xaaHC+Hdkwt`PJ&CWlzL$xU;@1fJvvaG?jh}^LHyF+fhLbyC!UL~l90$b=!D1&BIvUSDIYOzrz!q@xEWg=k1no;grrvSF%F1EBar>_SDzChsZeV~VN#h5Bst)!5+7t+T9F^Pv-L4K{r~+ly@2^{qNA!^lVF@Xu%VfA`o!=OP35&V5dzQg$^uBpyvpBzx6g=NnN?31=@l>%&K{@EZ6-Wp6pWbL$9M|asY@gFnOs|nUK%YYLH+L@b!Ys=2AqFQKB=1#KW(Fol)^j5KY(aE(A2(v)Xbq@S(~gLx@Ss01gR>>FJnd*f>1v<3Inq~RI6b}9TZ7FRiC3zG{ULt9D{M^!2aGZdS~_K&0cea<9Cf*%>N=B@Lo9ZGI!<tTZJ^yZDKT~5Ft7YD_23o7zep|K0Jo0nRA@|`71!qq;7*6oBhemSdB4*q$5XbT(9zOF`n^kNGnN+aNW>o%AYqd>PA+Fw{>-8Y77m6R5%~5(GO?H8PFJ(sAf7D_XB&gLGTten%#!+-icjN%p(fA~L;<fv`qPXBZEwa{gY{OQ;u+AqGE~NQS&q-$5c(=zYZ&M&_7zItYD=gL{=Yo(&6Ei!q0RlXK9#gs`KR%utqh17VWNBJ>?K&AnXSNNA>SJ35Oaz{G(%ut4E(}MQ%0dnbc62l>JkUzhDKYc-dYRd<!P^xLzL-+ZYj>Qi~XxOaK_JCk?tg%vtaSCurLGrF^sd)sJHyM`b~eF?r$}(wlY&Z;T)g`LsT^WglTBPs*QanM5VU`41%sfW;@@ww}9BKOI41To1ECg+ls~!5%2|8IEF*P5Q=);fq+0tbgsYZAS-eI(<yJ_P_nQ%M`)J<*KftQ${=oXMGKCY9}o5)G)ExB?@1`Qhb6giU%krA(PU0)!#FAb8v%Jh)fz3Hz)K;|JtJ=$r<g5$8BMUd?tp)|L!+4|PsBq$zBZ$aN)jBohV4sM=J@hX{Ot}<F_c>-)m8eyLnm!?atF-GxV}!hdcK3Swp+(qCL;><4(a)In8(v&H4bkCuIww~()t$Cg$+XU1rM$Y`5}o6)Z!+<00000lMcmS=iH;W00Gek;1>V@IvQbGvBYQl0ssI200dcD', 'argmax_final'], 'argmax_part': ['f5970079fbc83b2dc3ebb5c5db5e186b73942d27a73ad392f1e69fe3432064c4', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0xaaLR|nqkwt`PJ&CWlzL$xU;@1fJvvaG?jh}^LHyF+fhLbyC!UL~l90$b=!D1&BIvUSDIYOzrz!q@xEWg=k1no;grrvSF%F1EBar>_SDzChsZeV~VN#h5Bst)!5+7t+T9F^Pv-L4K{r~+ly@2^|NlgxjtV3ih&KQ0vtT@Cv`e`!4YC+*Az;hIId)}Y#QNM`frIPuEG2;YUR<SM>BB`n`^14<g$C|U;S(hH?`jZj-M7!y2U*I6v2PQ{`?SHUm`;{<(n;Z`_OHrp+NY|`A~NKzsM57VJL0(@K=AO{pg4BYyaaiPb@ipF7zM2qIxrhRB79*Y$wwI)i7+<L6m-ec2OAo!xUH5<!=bq<d5T3gGI3a3N;1cnVvnLKYyGcC1TSaw54wJK4jf|ORvUbz2HaKCd)5Xa?}BjhX(DEz?3J;1dI=yx_RASaH-@3O&<>}+pgELDF(#KTwp)x!u9fk~(3Rh|zAL3?;OkXdhIFYY+*7VE>71`?!^ktN0s`qc8&XN2;2>VY-FEJ%{(ISmwnr|Bq{;;|q()sQn>99UxW=JD2nG)u-z@K9NGlIH;NVt$VY#Vhmf$Di^DB!Or{cphJM=oipeuad`(P2XTK;EM;i2W8Hs-Yej`9I#!@wt%~5f&>8<)#fq1*9?Y1gtWe6kTXS8082cseo&OcO1ncZ$GnUd$qy!x{a8sta~UOhg!Jo(L%jv?Wq2p5Dgc5#tR{%*Cxag382A_&4S$U)3klc9R$TeLkPPJv&kT)u_Tz@ia#5v$2~S&1!42dF7tp<O-nv!B(_AM&NaqL+Y=U1V2TEo$Xt%WLXJ~}|_bL&NCVkIOsgh6TA^3kI^MV714BBlK&ezVHWOhIU+mhiUj7~#9DwgJj8~EB5FgFS;{t*}6A+NL&IbCC9+TG(3=mb1=nomk*^7%X(zY|n#KPuuID9`#jCJHGF{3E8E>AIuf5JFBfiA$*suk&wFIQgM|J2tamKu}gH_UM~nq+pgNd1tiuIkikX9VK_?20PS~W%9naq$*Qan|SG-bHJlpD5uZ5nP;%Yi|N}`?#-`7JoW)6C{0$AfB*mhr?_k}S38}E00G_x;1>V@@2EGcvBYQl0ssI200dcD', 'argmax_part'], 'attn256_gate': ['b2c6ef4a50b69faf76a7bd823c7c1bdd9a40083e9e1d9e2cee19446da730d856', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0mt;NnHRxkwt`PJ&CWlzL$xU;@1fJvvaP7r$x(Vnm}9Zz$2)FLLhXm1@3#*oF)uH4lTxuc*)c3#d^Xgj(yK-F1K7q^?IO}&S;`}5kTh3xfcKSVy^EPEY$Tvne<a<W5NB_N4tdVfL3RYAHqfIJAe3imbd2NF`_@43;tqRhvv3}0F)&GW6mu1y1<smJOMH3mwa!b$(w+E@8B4F@WH!LcYQ<}vi*>c5!VizfOpW#qf8yKxz<CwMietEKz7vTWm@BcA?4K>({l;>VK&hjar3H`bT+Lv>imvfM2tLKF1n}%VKP7xwSTubl4lMKbZ@+F%&_x__BuES->9}=&G_P{bd`cyygVsL31A;mowYcy4)54Q2F)~q3nM$nf2x>IO&`&NE%9{S!JG*Z*BW|qKnt)oNHL&Q{{(ls#cSE+totk|DHL#((mvE-h5fP51~<{q3-<Wr6v#F0Iq3!a_5x72)!hS76^AMrsgNIK=7<0`%s`Mr#-^s}&mrcd0Ct<s4Equ43z;=d8F@<I3u^Xr?P88eHKSmHsr<W^c7zA?i*%(nT$#RxNf|EKj*CClmNaSC6-H<~$}c!~a2-Ol<n!zXO&trjdlT?=%ZMc8EgA){v)G0TFrCl4=bA9#tkxV=Q@xuyOn~3g+I|UF9G{`AZwwDu&EfTh|80~3yF&e}KG~sBkSt8M32|#!@|Fp69QXXZuHbJ*6kGNSn7IW-6C6<P`+rXHt#XW2ke?vIT<9i&8j>!?wCChg#~=v*c5x$km{|E@VJmUls#ipS`vvYIrIu9R^{||~#xUoO`zR7cZp<lT6xcF!yLvlNTKO{~_^GFy<N$?x-VCpuAKIGo*~*l8Qi3-J@|~Qcyjc@G9SmjZwP??yJMiOSI{K;1WWGf+6Woy(fu_4HKw}Gef>}sm`#F2-$h6Y%+4N-aAK^-ut)j1AL@~NyZf4_obEw%iA7C30vs}4AI>c-&CbFK}Pr`1HGfwnqe9WpLB`^aiL(Zly`%C7&McNRR((&&}g=rvP;6t5jAyg13w4NL~0ROEi9fL56yE#74#msy$!3Wdpm9TTF?#2{U(|7a2;>$(s00000@P=5o;e?He00HF&uoVCRO@sptvBYQl0ssI200dcD', 'attn256_gate'], 'attn256_merge_step': ['e07dc53272322ca466ee61f27b6325024388b811c3ac23ec89f3c4ddaa087208', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0%`p0$l(<kwt`PJ&CWlzL$xU;@1fJvvaOA`q~NA3&!+|U{%5Swk96Wi!r+o$k=l3ROd*((F<{mXCebQ1>|Dw<7okL42FpDxJsYhY2o`>&}s<IDB8=8d73&qnNv{QLm?YFd(4dfyzCVzY?SQJ%YJpEx<GSSZ_aU(26Yo_$F!L=N8VkK7mcnECVXR3FWQZb0W0;4HkV6xbPYK*cEwUsV4oqfdYsT>xcWs!Rx!3%o1Jl&!YNJVipu6J(PZA$XD|<_-ft}I&(q(;V_9gA5mIBcciplqdssiptnxT5rR8{^qm*-5esg5I!5h5*OhT;i10Zv-wz~H`8w(fWyV%I?kq+_)<npB15M<Pr1J3ZH?`y)fh(saQ5UgnZ%4y_qXbOReTI6Gx{lIkdqR`+>rHbwXqGf#Jcr%}=yY**jP?{+GDB8b?(mJ$&8DiY|i$Hc6D?VPqfj^UfNws7l$Qx;G3kF9}5!qvxWsU-8(OtaPJLGiPBKWP<a7Mv_fpQxjzUs~y2f$}RC1Z61d+VLE?yRxqNOk8jm-CO6y8d^w@xmas+5lc*0hv8lES|sAY5(Z6*~4AwTZvp~=<trk_7{Ck&?JXf(Q~k7HDJ$}pDcNPq@bqzLNrO?zy|CAzd~@uA^5k-<rXyA?iP{Z<rm8N0C~DVO6tlX5g>03qjC}j*>K~bWa@=9&_p+t_3nlL{j%hn?>zmOe(FO1#nsGe6ir7D`r)Tz%nVC=S}iKaXrYw(ZR@v@QY+R(N!80r<uJb`mfca=wO`~>7MLAeJA5ue*y{94YiZewGo5VC%x&-$woKjh!?Q6{E2E|xJ9!+|TLdJ-Fy25&{U*pkmikd8Cyd($AGW_W3X@+VvUCAwVtg_(?*L+)2C5R0Sf<<@yQ8!TdKqzjXP1Rdq{)i{n%pGEFT7qjrnL>qNpR7QT)jN1PrZuG7=vbL8nBVJH=sTXJjcraL?A&$Ay<^T${3^ahIUeNkv2p7({=86jiFXQd3MfQB%5@y0s1?y3RY3d&-zURv}w;7|FD?oF#Q*>=ZXIq39sw+fD(s>R`4_UZAs9~W3-b({_Wle>G_U%o*pI^w76Jt>E_C6udIc5g2n6)pTg$s!EvF?@!!%KbKPYwUI${pQCzea=?EqArpJ=zPCUbVn)xDB8SumX@kh=)%GPzZdK!QUd=Q?rkB2D~#rT)#-0=1z9J{W0Q~Q;U{9F=r-0eky>($e~EyXP?t{jT!{E@d)%Iv7hU8O5Xy9f5RQ~`1u2srl2V~B$F4Tn9p#ZUx+YuOQ(!6NXT4{@^6%|dt98n`~BOeE%UaiaK8gsX^OS^xk59}x0QFS%ce00Eu|m>B>7o4HEAvBYQl0ssI200dcD', 'attn256_merge_step'], 'attn256_part_step': ['81fcdc0017499d446494331ee168193dffb0930c533d9cf60a0d7e24f2ba9f32', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0{j&(_H{Rkwt`PJ&CWlzL$xU;@1fJvvaLenG3p*4@#@C7z_UOdnQN}iUIs*fnqToXkwd`9YO>#fjBn6!_+bW?dkTRa7~0VJuL9OE|@vX0K-KKk%GFGBR3jYLB#l31d^{HI!(!3wrCV~oScMV*B7Z5(+BlK;VFoEy5YHm5Bq{ATXcv6p1c)(?0|uyKqz>At(LR;fARaiMGb`ZE%NljRxO!boOd$eqLXzHwxr1w?6acVYsta#(gN2<PVT%o_L+frAmw3C{&4G*|E_qU6IA;_P?iX8?ebg-)V3M_SOdxjw-(|ufGo<@Ek^`j49xkc#yH6XJ@Us$v&{qCbzSbl(G+Md`f&sw%(efIQUg~U>ucu?=}LDUC*4vcFb3eZdl(i#7~&XM7G23;1c?2ZDSnD+m6jltd&9g)O4K60a7J%|#DnS9f~-2_-j$p_Nky$z{_#1P!&A8%lUW3Vf}#q*K|X;RKV*Garh%ZUq_SCZfXl-yhJ`#;_N~{Z4IzNJ^Z?y{TbIQtEHbr(vXkEgi(|xeyPND<dvIChRkYih^`GNqa<G<f2h-_L05fLzM8Oz$su9Y!np&$HkNXew4XIr1XX}ah1_#N05)zz;pMpE+2)JTkOGwOKn?X$h(LenZ?A8p;hD(~vgM95iHc$`V@+K4c<D^rn*er}tefyCwDq62(#;vqi|6ZhbBP_$es%eV=l~*<1Y&pfvI-EiIO`ueK2Ltw#@rMnL4O^IsR@eK3xm_V!v)$@TikabP*r;;6(gz)~Mpgg9`wZ#*PS`+bwozZSFZbTU+Qd3I$q*gEguJqZ!H%Baj&oI=*lc*F*4ZrfaMDwcm`+bh20Ozaz!2PA{Nz+8a;YE@$UthkC*1Co6s-edZN^&>xmswdOpw%4&Rt;vu(d>!u=Q#(m`um2i-Zo$Hv0pXV?^QVeLn1aZCkBg*Yr?}y*9P)N1Q#xizh7jP=@-h>p(?9g(F6qds$@Ts7qVHsece`1nY0ad9&iMF5xMmT}_yss(1{wzjtf;hXhV6Ug~sdH%BXgACVF;h@GW(jJxjpfsez~=F)F83W3P)qCsVP5dR^MPjf%ndv^IS>*+dot~8ZGwCFufEV$YeWwrl2PZZUTK7w)*@2RzpHQn3xACSZlYG%^-^^xs*ILX4pph;(V9b1KDG6}dt`afX5#AGmq-4;+Erot{@LXspb)6hi6aB4ZW4~tNhfT}^|!NJ=n-lMjUD>ZnqG9vrL32?DqeAH<;T|FxK1^VgTJpV%)ECJ{axxeG!5K=Se>i>;1>bbtWNt*6u?=Jxra*Vq8yMi5O`xNmSW33Aw0Wv_>IPliElHf}r-5w@q6$tcA6oEq^wsPl*)*?1nqv3+!fh5of$c#37la>*`q!JY?Ow01rk%k9rEcf|J3D<Xym+1QQj;RthMJt}vqOwvt`6!cIRrC#^!siT-=1a(+=Jl$ghEud!FpO;uUNvJWJ#TXC>8lJwsJ;F-PovL4QG5(SEs8A4tuQ&hLGLp8oW=HN!i6*Gz;a<;gpWt@lH%qLhs$c+^pgetz>$LUlGRD@OxP>HO^0?q7TPF}eX&m_iowEJu|0_7#z6o8gxp&45e>`L00Hj_&>R2&cKkmYvBYQl0ssI200dcD', 'attn256_part_step'], 'attn256_prep_step': ['e9fdf75c9c3f13ef1d048ec9722bf454ec9f210f197b187b9d3bb304a88f1232', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;1pj4W?cY3kwt`PJ&CWlzL$xU;@1fJvvaM5Gqie;4@#@C7z_UOdnQN}iUItF&+o+2aOKzX<3>H<!gm?Ux(YH-uEJ3@>{ORLDIU`7T>6B)4%j6+JYTSoWbv@S%GsOz{==%YIcYF(AX#eb*}8jPlan@=Bj3zDcrf&7r!LMc6ck9Lt9#k4?)yc-Hsbb;^`#C1(!0TnJ(hIUrh2syH64!xG?r#aXwrXGZq$)3A+#RV1mhJFkkuWmQczq%3WQ@dE%ZCeTThQsrU`gsV6s4Ji1S$4g0Z-iXwTwn74WiNJXJPj$vhn_Ng)}%Z(J)U#y%n>bQ%8db!UCbe5#6~Qv8~HT&4zKkUL2jcl~4DWQrRaCR_AwtZedy(5GTOpoTkzCxc-L5_fQNnkMZ8ZcG@;lr8)+<y5esjS1~M`21ln!<dU@?&PHVvwLs3miN^A5bd$l3Y(EvU{HTqmng(Qz1p!I(V&<5I*7zU1JrFB{^?WoX|H(gdw>^CAaViXHFfTXekH^D!F)Qe(GNXL+_O+?W0#Moc`CE4FmgA`9rcM1@o{E+w&he>I_pO1kK0K$6mnZxN+)yW&d8{yq_}Nj)cS>|O4HI$CE6d|*AyV4Ci0UOV-tgJ5GGuAU$LX;8j4S<Q2ojkMOiMssafPXj?2M%xy>z%C8d&lP}<$tOV(x)xuesW&~5n2H&Xoa7|i}tAvcW$biSS*bc(5?;vzA-)~;r!r&Km-6`Vj_jTLvHXTnHbZHowa1j;gtv=DpxXrZ0(;(zF1bMr?nrA-;mk}KX?*vHR)QKY0NqJ<^WPv)@~+{KjTZN@acJ{oRB$9RrF6|UaIY$X9O@&uze%X$P7ZoOZ?&Yd6u;w#XecO26B<Qeb`IYNX6P%B~O3@vz@8UUMZ9#O=H*T;~4+D^72y#!qiustcVNT5(&ldC>5GP&lke;?^(Sx+kxUXtO0z_$jlhhiE&1-Dy4<jig<f)W(og^hgbhcL%suDWQLqUfzk6o@RAp*T<#lMZpU@j7@B*dj?K)Zj3L%I~>Ip%(G&={?+0Om+t_NvQcJ=`DapO}*oSr?D-R-PXqf4$aG|>f%$m7ZGh=7J6JC47IwSQ_ZR{M;b5bPa#Trtx^g>e&*Z?>1en@$zGWp%7tM<?tw%2A$<G%5lBj#+a)<HhDM!E05x0*JUICCph?-Ejf`i?LdOCX{=<0nP$BrT1UU6th?^>@IkY<w-x1oA)Ul|`;R>a0Jh7_Q3r!%<qAt!{nev@bwC6!We9xSK7=ivHp>iSB8G%FY!ObyvtGQ9A$?_xoM4ybu5j0PT<WrjI{QQr8f<MZaVxu^zbqx_bh)1MmN+rX{7$v9_=<lyq^ZxJotnpQ7(nnNTh6~u#HWsDjLL#!?IhHLb8?fwvdv>;WMyNu5A_=wu#sM8)lscM7GgU<C-7l6HYlQE!3Z~7;Cm$uSl!2!}Ea{Vze@I{X#>NTWLr_69BbaKGOindg4rW*VlL@$JK8}dBvG`jI=?z6-d#LQW+z62xsJiy$8kW|fQ29i&<l8=E!?aJ+;9>+T|Bolxb5`<X$YUr^eTNN-I0R>G^l;zM7J#Gyd!~2miDqON*labt_~5wrm<c{QOL}`0rSayzHtlH?8B3u?nFCWdDxA`K>&DXT=F2e!iiNT#O}@YEJ$LU4Fx7?zPqb9)r@Gw+Q*@UizD8pcm(B?`cAs!#U#LC7E=dJ7+$oz4py>(|C2ccPaB_-~(In9)_AcZp+Zt~g@5HcGcn3%mGkn8Q^xAj1HKlQOT(zb6-T(jqGZ68s2L42600Dvv;3xn9e+JwKvBYQl0ssI200dcD', 'attn256_prep_step'], 'bf16gemv2': ['4ef73f616043b8bf007b025d1ec62635be26c80a3eeb09a681d0f38386e9aaeb', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;12Hu8C?KBkwt`PJ&CWlzL$xU;@1fJvvaHj$IH!PHyF+1xgxk(N!JKGgd67`HEhLny~WZIRxVL=zN`w5#)dNXmd?d`HxoJQos<2)$J(9?pmS~=^~Qq>sWKl&m54q!YyKZJGH9X>D;T5e$D~()Q%G&R@^owt`TfA;;sv&u9{fp_yF)^>ESHqk>q*JNj2t6*6sy=QNPE{W@4&U$)%D8S?iJq6mLhVJBr4DenBsp`>cMz$sPz;_y8}B;+NQI39EtAfs4l@7*h!>u>KytZep(UuC|bT_k;q3!n>EZvL<$wI{~6>*uq*B>0PfS!oKHfm>2cMCz<!l)_@#~I=I;ox@__ucJ|T<r%7_&5JOyYCBZIBT`76uv^(F6%Lu&3R20tKY-$(vt596kDVbKDP))N<Ca{#JrBkhr`g#a3>ZvY_YTusU3_oa_2eBxNgjbE~pry!qON>Vfh7#gGu!CCOEnHNGnV?zK2ljs?IlS-68{`K=ZAUjt8p9l623+0rtLM(3%Eez=FlQd{sxV<3!kun86c4AgtvjJe$A%`hIo*@$hkMH${Mk-%*q^(S*gU<zx=C*KRP#1)Zd|f+BC{h)X+(vl{o{x0XVGH#Sr{A7@0`w3j;rE4!<l89RpC&eRYX*_OtD4r5xeap8=fuV4-zymki)E!xcr{A?-jcxS9FW9{0r_HJn-Y_5%2KJzQgnn2T$}XuX(SgqAVOA4!76n-Oy-G63$X67uv~m1!BonUxV_99Npg36Zl1&LaD>J{#2Q$ef3W+!&8S*sv675zQOkhQ|53DPMM<?M7MZK3<TpTXaXICqTihbRu)_cU!JFe*N}pxPf4^Yew-rNS<Sga@5r#9uQP3J&c?^l+*IjTGZy2R8P4i(MgyD+Vm{{P0;};0DGk5-KlLT~({Tyy{v(>U|=sxeL#}ha9(X=->fmtH4KT;b~Kr}0(%$GoJDshretjZOw`!?S+AwI~-E9e8dx!Ns8JUOcz>mphkC5Nl2b{D5Q<sy8Jot?K|KKF#tqTtbhcbO)6fZ!}KYp>X;Cz;*Metdda9YPB``F^Ytec84&OyJ!C6Mo4r2%n9DKZ7WgcVab~WcK>R5_U1154E^11`B(KZqw;r%IroB-U3r{knqoMe?&+7Za$UOe&a!~mRSUj&p<z3a!m}lYzN!Vz@=QEy$f#JsP^=zyLd9El(YUQ3UJ+nQ5aNi{Z|_ExJhQ77WMaHs@`uTgrlHXGT;5q5usI{@Hb^OA_=;(tn9p}t<>j_g`$8?aalKa0m4qP4u}g4mq)Q*zj@4)fJ2cPP7EsptOEdgQL30Oy!8yTl&x$B^!aVZ3AvN-pA@<R>qQp>4rC9|00000+Yu|cCqVRV00FfK@ErgEUOT!gvBYQl0ssI200dcD', 'bf16gemv2'], 'embed5120_step': ['f3593c4b9b5c112f66be07cffd8ce2d96025a3ebefbfe04b54bf886733b2c4f1', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0mV$EnNUVkwt`PJ&CWlzL$xU;@1fJvvaO%czb&&5~mafB4!SYBUp=}k`1lIZ#|OB^|`ihA||n|1L(V_w5Qmsj(D||zC#TPwV1Slvn*c0{))PX@uUx9d9PWfO}PdPRjx+c!R!Jwg`onzCYSDpz%@DXR3*VJevbe%e-twm7Q(C;u{&@BFz6v{dL*Z>ntyL{8*z09KAwoU(T~x+FIARG|7%Ke5M34_Jj-IMD<m??kcM$jmCY}*39O3*Q2VC4)gSBYpp;{f4{9;cw0X*HpICz;PI_W_eeK@ia!ev6eIV{GI4&~#ye%&6g2hk~Sn=lf`k+bxN6`1cQ0->X=ox}tRH;>+NCVf@M$Z6|$O;wQ<jQHf<OP*|8gG!Ljd$z<X$PLwpt&!gSYm2+x&8eut7bjGc@(gaVeBeUQIoq(5;z>UyL@o6;t~~R<C!FHYLq*VMKWTE?L#sR9^ZNcWoq`JM9hS7&h{dF^~lb);M!7ul;VEtonC>t_>kaL$jmViGagp;;^dIRj3l8ePX(7;&>LPvXr+;XxMg|hA{sXU9Bk&tIbZkWM}fyzf|9f>9lK&Stub{n6u>#lEG`31NgNggIe0xcW86B)oAD6QSX-+(jYUD9n+v>ppWOI9ibvrTOthG}=5&zV(j2XCBJzl(qCP*+_US2D!HYGt!}C=Eg*fGfiafPj&AI-KuwMh6Z-UTe0A3h1V{jH>^@9dMd6hGR0!FNO*5N@Tpc}G=CBG8S<_7f0ziFH0pG^PQ<a)6ol;B{KztVOOagc?ITQFjIp1gSa<n+cx7l<KuGoaegLwQ|V!pcnKameA3jUuz;0z(Spk+N!4vMGkk>`>n)h?ZkLnnUurHo8U#Q`M7Jw{F+^3FdM879GdMC*#CD*5rTIjk3Z>S(;-q^3#_tS?D9+)w@DddD-~<eqiBx$qjm)PMfXpm{U#Z<vt;V`|lA}te5@J?1iYN4Qj;X7^D+W&>fxSZ6vGWE$Gfub3)P~%Kcu$zRiy|aTOV7P#hSU>taZCz!?@NYo}Uh=a@?0LGaEH0&})M00000Whjg2q&z!y00GGcs1*PJa6Z83vBYQl0ssI200dcD', 'embed5120_step'], 'fp8gemv_b128f': ['72049eeefffe5431c0f8972d1d9f3e4f93e39841312aeb492ac24f455d23adbd', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;1bUStz7^=kwt`PJ&CWlzL$xU;@1fJvvaGJ7nvB>a%6d84Pu#}3k|iTw8JQ>ggj|iHc#RMX$N@X3BV{ha<0FgifXs)MYP;JCl?)@MoCg)!>&S7q1HaR2gZD_25^*=B$18uv|3@}mI~A)Bv$GZ?)<q>M(WtYcUZh;z-1%1Vr4yLApBzGXtnm8ZBSwFolZlR{Msif04tWV9rV^GlOp6!yQVR&bR2hiV8o)7#@l5c3zuo(3o-?JJmcrft^VWTP!9(yHGP?4zRNhMsPe|n0?<mz$b}dl%`%b&8*SdUE#sFfu@g#=cr0EXx&3f*Z2RmXWWOhx1ajO(D~jIwUhU6>;FO4jRlFmrx$>AF`WZ_mXuho9gFl^w-;Qc?)Xgvu;~eDCwOm>>f%RM5)dW+m-63vNl<6gJVg@#0d;>f<FFanTsJ5$vGJa|lEohtiv~omCAvZkDXgmhr8?-z^PMvDa4`ORSQ;GHi{tVo9*rUYf#{g3MDH04Pyl$*puqv!&tsW}Ezoq~ZHuS$_eFt24QswiFI%Bk?p0;T%ybX7YlPIs4@*NDMD-q+$X(_EkSVh#UnQIAmSF1Z-#aNg8l5I$#S5Hmk(+&YMvSGv_P>@T4x_ppTPKiFiZkD&$%6>T|USo~8@62d$@7Ix+Gcx2w<4NGa3Y|bhXARw@(!%D(3$g5QoF?I{$RQW->QE3}W{Y0a#WBP*%^^kvgaY9@{!h~qMJfgw2{wmUST49yh|{Wn0hkrIa}b_XD2+I@-d;SpEpreZ4Mc4skD9~3_UMyb5nk<Gh*)HUH;*6R|41+PipinZ2111_Qp+pHJ|ev+xijSI`v5K2)VIO?ZCWU3_enSbkD$U!T~MPeUR$wb(|H-a*Tj=m@{!F7%=vexo({8;RA)Q*o+g5zNgy$&0)s$UgxI`0@7$q>2>bat+Dc9xclO%|EK-pVT_SyKSNcZIbqQN)GlV#0LT?&fuFB>q;*fRIexyEBIjPbK{F04*J9N%NZuSJHXxt1n_yPBwIO}U*IuHUIwg(S!sH)xEgeQhTeglRZ4=B#D!k+EGX%pp&7k}f2FzoMNIg+aY=~lA))@RXFFHC8Ni&g!F9Tii*mkMtyS=8ekz6xLLTBm?RKkRRPr0E!p4|vPvX6WD2tmq+*`BPXi>}$IDTQPf*9(ne8AYGUofp}Hb8Sr$e|1&B`=Nfbb*I3c|(XyEdRx@gkg##n*0PU4q!q8_$8d5}c<;k-Mhf{-LnU0h=Ggj@UB{{ktX!fc$UDmhSJnQfGs!ALoh>-WsAYH)=K0yB7{K+9euwKuE*hMhPd82i$tXV1(IJRk~0z|5`202a}SgO+K^86*CQnN1MC}OIq2#<DHg#Gv0)`!YfEQHxT$=b!13$_Qx996#PtrC6k>W*&*T1SMB9dx2SN!2$*vj0pphw~JhZ9D;!W_ZuohQRV4??sSGlC{mCBdzEpQ}VTgqa1Oy`fu+u^0nN{VLcua^q$%-zpmL*&nM8CuXmKZCk^d(Y*x}e83NN^A^?uuY58O=AZo?Iyr#zy000000w53~a^h?G00GGf&?Nu>Ld0<3vBYQl0ssI200dcD', 'fp8gemv_b128f'], 'gdnconv4_step': ['df8d6f11ee18e1220a0ed7bcfae96d0765e4d444a8d0934cbcf72e7db52610aa', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0<2{LtOwrkwt`PJ&CWlzL$xU;@1fJvvaM5DKnao4@#@C7z_UOdnQN}iUItF$>TWEaOKfw3x8Z0+al;TxumU^bJ;u4!e#Cm-6!kiW9OBv*-6&y$?TvlOUtGWX@_+w8UBAxHd&<St7m|q<O*YeKJkk^%fGE+S4%iokxLn3D}ww#=ZOdy00Bn6Dp29O!t{tSl#ggZ*1}r1@#C>v=pORBWUb}US=;$x9lQ<0Ve!Eq{r<-2#%tz)3-@~LCWi;RLFX8$xr*_+t2Zbi<kHYEW#TZbWoBpZ9afj{!wrDe>z-78heA^|gP)q?yE_^bO+_OC$GdxTDoyZ&4w6{OVd<$yKGR|)_!9TSg<6gnbUx=;EpGGOtOd?*U2~)0_FNtQ?6k7!0QRBjV$IcCu5I#(ryiAV*3+$@YX`;a>lUl?LPU!i|B-Nk0s}IQfe8bgTq2i6yQ+SF#%9cfZ0f13o(EoNHDM-c<H>HsuG{TNO?CHC|HT$|>)iT>>SO%Tq^zWR#0p#<XBQ}4A}OdB*Ia{N+hAT3bFn`Z>Lc<*YMZZ5vZz(E;UzDC4-Q}y8OT!P5Zxya<EJOo0Oy%zfaP(y!(vGnV_~vK5Nq^~5utkbkA_|=&R8|x+$O3l@*z3|#%T4|p6!dQf2FCu*r$I6MLEJC#7wPjAuI{>Ts*-%Q~cEn#4oDKH`}}g)t^um4CiW-TB(V?wG9Rm-$kyM=FIrG6_w`1?2z#1az;!NX5yTGm^~u#sC7ZsX@DshGq|t}3U8~XcqX?ml^N|@>+EGtzQK0xc)T-TMtRm;Q929Uli+V!DNz-GP0|403<xjRy6~t)Sr$`&Vxw>@@N_J!MG63i{Sj8qizcbyIp?G15Lkun&w+x9-ytVs973b@)_9Z)3az|V{Qs;hBDXN3h95u3ur79tY_GMX9@^z63az?hRDKb-8XBs;v-9^XYx|yeAl7%pSZt;Ti#m@e87G1*i8ydj_-ZPPF@7E88&T?t3%i~Tw5YpHJr6GYZQ)7O*1Y|~x_7I=z*^VAbF~H%G1n<63r}}Z{=au>E(^0J=jAX_W*&75`r_R=QBwf^PsSc?{e`W6U3iamYcDV+JdmFh7NZ*ZPx5M6eb|F+4uFo*jQx=CNL6%|XVDsUF9PgG@c-3Q^i~do^)tm6>5#Ct3dqUj;fST%tkn4jReN#km%}xft$s-SZ}_WkB6K<L#$zA*=AMiARd_dDinRykqzKA2wNuTOcq<b>5_T;V#}07zqiM2^SvdkUmGAw?C5=jc6jV@MUC#iEZK(7PO99KGHoNQ~qknaRT<!I|F6=z{qqD;H5v&kYP-Q@_<D(-(eXrMq4YQroD2P&7Q~}-eMB^KY*R=rW6t=2TDz0fQv>HTUB}|ZETctPtQ^u%;FLZ1a6X<Vdx@iCa3vr{hz$<wt00G|!;2Hn`cvgegvBYQl0ssI200dcD', 'gdnconv4_step'], 'gdnparams': ['9cc7e5ed4850b6033b8f1744f96968bb7a5fdfcf0e9c9bc6fb3598cd8e7a5b05', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0*r*;#~kgkwt`PJ&CWlzL$xU;@1fJvvab64i0{f)C#}G9<O__9hp%iR#qb#Cit-9?wR`&I;SbTUm^%pUrk2hIRNPNUQ)5)Be45XG~KR!R5Iqi4<s*{N+M=(2I6H14UmUAF`HwIkUEJfK1+On7}4W!bklb50o9rzflhFlNOE#a7jy~a)Np+@)M6YqhpUXx$LGb^{;7(x7iQZTV|O4JMQL=ZA;*xijA73&i;K-~*rMvqkn+NUSz+mV;$6?s<fu!at<!`HX{0lohpSUR6Bo(Ni<#ZqIf9&(H{h^2Ea2vfkI$NR;$Z7G#-fc+jBzL;q%g}6Hkc;*5r}=&5)EPeP8y2G@8Xg7Ka4<gPNFr<h3U|3rU2j^uk_qQeDtyX(MujQu9*q#I8-s0jcoi&nv)bF25dtvW`!4yQINr|!7a%m1iik-_|?5I2-+iGQd}MBX*7jy^yvybay_-qJ65#`T-TC78z?;Tsvu-p`2ZPnsq}0t)Gm=XPOr9n@O|J*VOJTy%1d_}p`fez0qhZ-f-wJ()Ot!h3c<L%JiZkb_&)FxxUTvJ=iTj95L%;rHkng8@jR8uvV{bEN`Ic~7f6uRREC7hWOTA`i5u?0{}<q$PlQCmuzk=M_yO3*_o_0RwT)oV$R&UU9P?wS^k0ZbL+}rQ&)~Os%TyPN%_S{6uiJuSDYBXSon(;HLB^@$uWT+hEbLcp8PO@|6Jg1`cv;P-gL7J|TK2tPuQ9qdQNPa2=WZjDX3&_jK8W$9$+p*q5~3g&GByDMpHcj7Vqwr&Sa(eClp0ANso;m6QrBfRECK{x?^&8>Cgv|U7|Q5CGFLHYq6R%mxp(OylD0AF^2N*effCJi4@d0W79tRf%Y1nvsgQ1562#VXIhkQlmyAqn;(p0hkr_O&Bl_=V@r9ok;W(<(({~-N<EfUR{CN6(U7Y8oRETK#$2`iMLp-rD-66Pu77V8>-#^~i51zZGM&7!c97!h8`VU#Pk)Ji;4n6^OfaHQ5R5~R`dGHsF2uLS&KM3rGoJ8<JuLT+?a4*%Q-Tm5*Yy8)-^1@Y?Jh%}Aq#jJ;pQ_&kAf3h(x#wL*C&4V0&=ym@84x#WdnE}5r<06uF;I8N4$O;LTwqu!&elB^XNmd;kanjeEq&AhUJi<tj0v{&593D`MtY&PAs);>O6p>#R#kjOd6Zv#G<6ZH>+dQb0d1~8<@1?H0>@?t;Z$j)l#-~kYfSL8ZiwlWB=JLt+a7FUtt_`OxZd;Qd_#m)V5x4h+TNZQ|60hovvvq_Z~y=RLK-D_`v>1800I67fEoY*Ip77NvBYQl0ssI200dcD', 'gdnparams'], 'gdnqknorm': ['387f6f78eb0a5f24013c7818c82e9a77e357eb3e91496273ecf0f80ce71025cd', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0#X#Y+V39kwt`PJ&CWlzL$xU;@1fJvvaLemJ5224@#@C7z_UOdnQN}iUIs*e+Wq(Xkwd*tK8zC`Pc7hqw;AtTCPdk>ue*u?|Gw3O>5?~Tqe<@w4Be@Z(JP2u@Faq!W$WmY-}?i)*@Bib!+>6@~qLjBoMZ%4mKx>n8-zKorc2P40T+9l)7l#Hb{0~8s3)r{BUcipW-0SeRD{?=#L_qnP>OcUDPn(=7%;!9#pO0^{8mbOz<@7s|^O@#BKpakW&qn!InS=&5@E~51&#+yeHF(EEi{~2kju~*}w2!6R9zrIv57LraJ*(o_KKDO3)paK|s*`IHP`ljPa3B0f1@#7Wjk`G{F77Ji)H^B4uhnOUwrEdeL>Cm3)0HTs2PX(0WE8tdQ72+<=n2iw02G(MAY%go8XsJ_&yZ8<C@(+`XT3-K3y5#`SW|%(XUw-tpu>NG0<MtwocTyk>e2`$;%wD75T~xeFK?xz35bhXEX5D7C$136}s!Fp|d`zkJdABN)Cbw=z4_F<HG+AWG7XA``#Cnu=v3?n)Dt;2{HsHh(B+Nd~Q8;i4||s997mJnm#{9KmH0)g)3oj!#I5z;hytg1=F`zTXI{1{A9{jlSYTf9D$B>_j_DxOvP$dp#dnfo?qQ!bQLOqTZ!c(!S$F$5R%wxyEy7a(+2{{%+_qVVA6VzZO8Y+Lc0Bc>Otk*h_TsSt;Gh+Z|u&xMM8*_R&-~)1Gj6!u}FsDZm+a)=^@7?<fxzv}geZu|-@57f)iqjFu0db$sV%x*wY^=Y8HGVI?VJJy7M%GD_4KU(YkY@cd~a;2nE9u9!57dvfmhLC=pEiAjB?4&zI-%T12sVW05miQ@^_;7}n7QAFHcAxFgIoHt#cYt5?WNY1-lz@1<{;ZQlWF0lqgyV=1$5;ow6(%Gfj?tf6b$^Ei~=q6v^#QIzPFwyi+O|+03Qj0t$H>N_vdyX$`3@U5_tc7weCoM{)Y$X8bNzzmwJc;BvIadG4FZf^NICdneX7T25jZln7WLoVs+xR)vHr*-k((Dmifl9PNOyVOlz}hHypK8|8XYc+2EfspFukLCD=6oUGVGbE`m4C7(mx{RrIN<lBysRbawZAVG?!@VD9{&g^;kQ-*g7;G*%6Gc!00D>x&=>#!Db@G4vBYQl0ssI200dcD', 'gdnqknorm'], 'gdnrmsgate': ['d48e02ac4b8cd4cfd2449578d50931ec8c5d458007f168d537288a3a148af090', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0`YX^<4lzkwt`PJ&CWlzL$xU;@1fJvvaKGc)>)g{R;^RrYreXUSH(eZ)gOgJaK_S;3MHkZ403a<SjSKP>FBMT{J*{9{^Cy_Ta8}8EI!IBdw~@Y$zp%?Nd6RM=@oKnJ;#RrFQmVomuCdShN8arH#iYodF;)X*7<^Nj-m@%ci6VEi;N16f`4N7Te_Jtp_%UmJXR0`zJ79Lat@*Q>QYkF4}q5u#rt7+Qr)fHxRxM*_$nfb@}o*okxV1+R44TwAbTOdKMxLp_r$iw;_nWhD8m(o{(OKH6-IJoMZpm;haQ%n<nNKb)a?)j#4QmL+x&^iWASBd)CX&;HBlz0{#&KjY<LkBu7wpI=>zYR-*3-2x<;2f!fBekwC4JGT`1>|H_uRlUI~SL}ik<1H{%=T!^E?vy;fdW>%g}XAh<1Y-t0sH2029mU%O%{DiO8MS97f025Px&ybMV8ji)2Xf?E);UOzJ)H%z~<S}*U^+XAKZI&!==V<T~x?o2b({{@#MNU7^E5i99bU7=b6>?woXb=e%_msFCHIlanR{t)M@4Mf^XF?@{Y7G8#`Kr0rxQ%ovW7Rv~e9}m7K$wf1l@2s!0X+B1e(3yi@t2D%o%P=meh|xAKM%ra5~TxC3v3mkoYf_3)&O~<93<+3Z5w+B)~5>{>+IbnqA)hTq#Mo@(p#O4D*(iH%BJQGq-KVw$6aZJ8uLWl?FyKm+$P%yPBp`7&r)9tuY%oeEn*Ixn~u+92-Ge(rmG3RPd$1l^wZQ9ZxLMY^fewUdRv^y;FqrIO-*D8FK0^Sj?T$UH62e6cL1%O_<&Sj<;~X&0`=%JoR;&r4Y9>Z)8Cx>OL3=C^Fo<ldc72cZK+?Tc{cVn&c7w@;@Zutn|IMY==)4j*ElZ`C<$^J*>*xL@YAuayX}=pcN+l7*%_+XzLd~@Qz3h4vcnzrIcX6hJFs2d(`FYsuA<{zqKoG_wU$X`7>iZ=1^Jnvr#`#y;!7YS3zR%=D@m8njka7Bxp!hVD`3evsxA_$wcb3G@LQR&!vj9uG-7gy$~a9rVj=()BD(NDx2+RtvJnfr6EQaDQh{#ht>dTGf)gF`yKE8CM7E;Tm2Q6XaJ)wUWd$H1S1eUme<a3xK%DL_EY^)}S1n9Pr})CeITQ+_91x1A!R^G}`8ov>Ds6CZff(uE&8b*6l`lR^y7JI9=ZZdEWHhVEqegH1LzfgzyOp3<Yj3h0?dM%aRbr?w>aT9<5VG;YPB!`)l5rnU^dmf}gr1DAQ>)zfPBT03Xu$uL?|VGpZr7kA+~nEHii!TzIEffI00000fU%b-(^CZn00EH*up9sYbWTw%vBYQl0ssI200dcD', 'gdnrmsgate'], 'gdnstate_step': ['e36ce013066567f07c208caf14316662835622ea3fb40bc9fdea9f6ed08b382f', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0|{LeO&-Qkwt`PJ&CWlzL$xU;@1fJvvaM_g)h304@#@C7z_UOdnQN}iUItyfBlrVXIe-R3lq0bNdXpFYc#|fnA|~EgoCzYO0^c3<w;{h-q`x3iE?o=(;x0(Tat)VR;0GYIWl4nvC-xb+>K{xw}GVVf70hWG8icpI%%^6CiGvzv;g+ND?O}u$3y;0AAEb%+(|&U-dV+^hW!^AggZ6vc+r5h$ea<GEj03*8KI~1%V?%8pEQakyBQR@OfA)va=LUrM`6UtkEr=ojETZR02EpWU$F)+0p9}US!xHV`9h1F$4mrmU?tzH<w^lge5?cxvGz^|deKpQHveUk-m$%4-1SczCOpY2vs=!Gpae%!EykSvhRN@)uL%F&9oe_mPGetl0n|LmtaFEB%1XFCDTqaP$iraMZx|POymqZ4FmShtf359ZnP3^n7LGCXpwI%PS^8BW@wuqCWQN<-lMLv%Pq_dzWxg7Zi&IPHpSeF422^AJJ%0oqaCL;nT&bTJIbjp~d1lvvVQWK^t`9=jObJ=NbcDtu%vJqgm~9K4d2b{$WMJ<pzDkJndMcG&_PydQj!_#wN5UV=n>Mb^xFY!&Y>&wt!aPJRlI`S|=yW?tl0^aj)L(XoT$5F&G;QG>$T8OO*1-{*nml&x6eSR3G;=~(4u38qqtOZ~FR&Cli8uC~T`w;_wV)#5n}01g&Psa>18>UxeVBprL_~^S>v#qdCL=s2p;O<@q7kG!l#XvU7NRX6>Md@r*~eAVB1ZMV4-7k&d2|blezp$>l|TQzgyO3v-*^jzWYQ=PI6xz5$%^yPWaUMco@It5I^C7t!!p277Mm(Q0|%ZIYT3%GMf_d)NdRXu+z^8#{g-+&7lvbw)BE_bF~Y--K8P!21+yox7(3&{UAm^nG7h#de2><RyEmvv@nm8no+u6Qeo?&no2w|re6$GzR>;{R-~$U)Qj8m-M)brPpwFb5^t#JY`+6v<rsh|66S(-=ml$&%&mTN0D+NJte*VKaq2fU+aB0!)%EulcKHLC%IR2UNPmcHJn6o-`Hae$Q4RZs*eT{_n+;;MKs(VvlxL$Zb;kQ;JFpee&a-+kYXnhz^<00UOgR)BG0rG)r0OP#na-4+lTP#)4G{=ZN(FC3}RGK9&X7Uk&(MZopM(@?PA0+$U%C-OMVRjZs7?f9}jE7fsJ~i5|q#MkB*5u86qiQ`g6KJKaJ+4zsqMdt*5FTaBV^kxbo{)D)j$H<Rv>x(e?{6cuCo%)w<~?k^0&WBCP0N@dkyYFS?WR<KYKHVbNx#l{Dmw#odh`9=$eSG4?S7{^nrE!UMDGiSVfn{tnL%OhR@#yNZ`SE9YdlSd0918Fs9_byNAkVPN^#+M>N8{zHzXPq6}jE)V1t7)6z*36m63Ri-V^UXj!*vl35C2^kxYrpk)8Fx+3PUI>B_|0URMWftLhY0^h)%DaT9OlSzGb%EZaCe-`sI{JKtUa000004zBTFJiAS?00Ef^_#6NLdzHeXvBYQl0ssI200dcD', 'gdnstate_step'], 'mlpsilu': ['2e22681a1fe0aa9a69796eec1326d4ee7679bda9d7d9985ae52fd7edffc5a69a', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0nJ3TU`J@kwt`PJ&CWlzL$xU;@1fJvvHNRkfxwJYZB=d{=lFiQ+iD9m})j7y=pmjv)B~Z^~Xz5KP^-{>P9*O*IM<ihk4Ob))oslpy{vWVX~hN|HPdXKNW33s0RbQoA9--snwI)rw{)E+Rr7hzbn!_Y`aFKEsJ+FaBf^VP6O&7$UIa=-lYSDT;-*1s^-5hMg45J^+<CJo>ZXt4V|u^K>oEhNxd4H6`p`1GEN@i*429PZb(ZKz8P<KHa#vGLx#vPkJ#?v@xf9U@#@OvmE8v$yZ-%oz$xN(mzFjczg|96d{!3wd_4W^*F;WEzCK=s5#;G3W!KN7489b(QMUJK!_Lb4pH(9!#ks1%k<~EZ9`trPiM%6^aQ3=*`(RyxX+@{v<37l8yZ9jfRyo5cU9+Vqt|31iAYAI%bhfYXrqj#em4D-?J_1v}ybHW4eL+s%!XZcN*Ig4?yiwHI;h8RvK=%xx0v8>s?_`B%QGs_y7V*4~2H&Xb)z_v)G<-5x5_?NYjL2C!Xe~PNJvcWAEZ;sliT)C%NmpY1^w&D^6V1R|x4Tb5!;}6O&|68r5gZf#8?7hipge~LUa~$1wSB0Yc;{-|HrsV2Cxc=~sq<%NI!FU$r+D*xL-xG>=1X&%Rtrf1sQhc=lHa?#Cp?B|KGL^|);C>1bvP>-wva?N{}Z_v;CGaqhA_RI)W0-rnE<^E+*rQUMXp@b5luI|D<JBnNSeCB^@fhA2AV_n;!q9Ck=#rO-U!Sxidrf)g1Su!fe#kNL)XZ$J}vD+l=3OXl}I^X$-3mkgq%x>7KIG}+Zq7_6TA+$1%n>(bpjG3f}<)WujuZZGsso-ZjL7qs&C8(JF5hnJ%Pemc+MBV3}DfHl+V5~XE{BNKhaMX8iCTe;$SE?_7Lhr#QOAte=X0fYzDa}Ld|yt(pw!#;4&AzaHj797-jj&6HRdvgLSnFaO2l7w|N(Jt0RJVQ*B^9p_d~H6QGcalwZ(jhqbCLhBC!`y09u7!6IW(Q90eMvCFa$**JGqY3)rF(#<++qD>=d{{lv!rTAw&8FP_H7)Vr7u8bavRuGksucYYUpn_pdQCf8`3Q@L*^G(ztjwc}r4)p*4lb<LfLl5vu00H*~z!d-hL5CtJvBYQl0ssI200dcD', 'mlpsilu'], 'readfirst_probe': ['3265577b17501a6a9053f16eb8885daebb4bd96e51ca44be75b9106e2432987c', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0g}{&|LsOkwt`PJ&CWlzL$xU;@1fJvvaI;y~?N?-;>`)_hKz+Ye&dr`^Q%H8%&GBq%JpdLmkYKZoDIRExmzWjsu0@itrwy-Es0R_*W<4Yi_GKH1qY=eWn0e+LYXM<a8!BryGaZwV8e3_FV3c#`UMkmgB}eKfS-G9I>Q4|HM8Z<gwp>&OMdehtRTy<XJLjua4Sde~#lEv6_eEn*1-DX*GmTNpGFc3MCo%9bsTyZsXV!QN0D%mpvP)To#*>*J%H^@d7C#D;rKlyH|IWHsC^HpwxIkiX-fx)2hKfzgyh~Z-wqHK)o3>3$_p95HJe|xU+}CN#;|7amK8HdJhAuOf&JSR#wA<ImWpdK@l-%DNVyfo<yk^jZY%WTjHDDTu1F`axdw$^@h{_!72iyfJx{3*qhVKyoW#ZTh#05q7wAP03dLgbI<`VY6!B2y3vvUsg7uw=$l%Ek}iiS7Q{7>;7#=h+*5|f)A*qHNLXLxuxRVtP_3UoAXxZZrns{W`(1Hzkrhlnm2}SOhJ6r2hHgM6!zu}m@cvW9mqMvB=}&J?!i=IQ&l6$dqv$Lh6_ik@)vlH0q%(snR<ALS8bkS7Q0}RiO=?RM8rB)irgNz}s|?BlJz6864ly}=OKi&k?|;tojI3O)6w5x*Ku}Xi50o}mU^09jG;}@$HVv};EFDYJD8RR|Y@VspTz$k*_zl<c@B~59kfw8nx!wnWf7^ZdH)9X|mN(Hr({LS5ROa0SB{Dy+{w=VUVi~4C2p@E}n0IBx9?;|=GiM;-qj~>Vu~jgnuct8-91Swj9TJQWzrbKvSXte?YRv20hRfjB^Lby-p$jiF*o<n5O-lAtyOouE>41nzPd{Qvy^$P2xcAN>s8Z)mxhZU1^MM#GQbwtqSwdd*RbOg+vK-k2WJ)W|rPRw5r2ol%DNx`5ErQo}2&TN?00Ha;kQ4v_Txwj*vBYQl0ssI200dcD', 'readfirst_probe'], 'readfirst_probe-zero': ['d87991d4b918258b19ff7bbe418d327a545ce4a7c25435526687e34cd5afa08b', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0g}{&s_jNkwt`PJ&CWlzL$xU;@1fJvvaI;y~?N?-;>`)_hKz+Ye&dr`^Q%H8%&GBq%JpdLmkYKZoDIRExmzWjsu0@itrwy-Es0R_*W<4Yi_GKH1qY=eWn0e+LYXM<a8!BryGaZwV8e3_FV3c#`UMkmgB}eKfS-G9I>Q4|HM8Z<gwp>&OMdehtRTy<XJLpq!rn~oyR{$4KaPZ4j71A=Phbm`?bgYY7<EqK@ux8ED~qJ2v<s7QSD8tlb;_in}2DrL>=M?#M0Dk{U1J3_Q+M33-zqll5f!tZ7o)O1Z@rVo>CsR+sM|~xr%rje1siyHWwyKqEGk1`MQf?a!h!41M7$W+UeT^d*=TMb8G?Dg*en-z2&^`rw7<To>vcfAN2DK|5^EjAMtHU1=s|#MXs@gDfW(G)^(2wvVh~u0WRy)aH0(Tb_>n5Mq6;>K1qf5gSWUB1E5GaZvh-k74EaV8ee}f$0~&7>JCU2H-kXO!2zOj6Xv5{K7(ji9WYHtnUSsp^Py{tAk`W$UpQLkn`Q+nL~@$GxSkDCVsz?$D!>1RbtX#PU0eQu8Y~ejo`u7cjl@yM-19B8PT%v@a>0P<kW`6ikbPDs0Q0TtxkwZWQAP<tiI>2J+M;+MAl-8kZjaPm^z*Z7#3#J4{%v^fz87(wTR%PPPY)W>>x1s|tSCY$;~mu!IHNX4zPHgf$s-eGl^K;#oh$l!pNe_w-l=H1Ly3o=Y@-|U{+W3f_2_(6OwZ{ie1irLld?Nwh&7oBdw8K^TOf2)>3H}#@}57XpQxXZ3!@CMCXs?k%BBkJ8VWbF>})}tQii#_oM1G~Ku3K_w73UtsVGVpoF4}&qi*W`Irk@$F6UIjG<zcw{n-2LJbRA&oT(7=#w>_fkex&SQ5*!)g^lmAE0@2YxLm%*H=!IVcEZUYK>z>%p$7`yM!~pk00HX-kQ4v_<XTzLvBYQl0ssI200dcD', 'readfirst_probe'], 'residual5120': ['f4d5127cb4db16282257e91c42a220f9141c222f904554f45b2019f049085e7e', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0pHxDO~_Rkwt`PJ&CWlzL$xU;@1fJvvaH;+uLnoHyF*Fq{x&3gx^QO+>*C^$i+`5N|`=?uNiINV(CF#O6vEe%l<I{%FECdVHyCc8_xnvl@mwFAB4!&RvqjY(uU;be12<>Wa~Tp9LXexZnNzVH5R-t&|OXT{D`EbUnpk19cD15=LMFN=<Vo#6cZ6&sA`?BCk@ROEbW`u@e1pP>0b;)tRs@QHGq^!zEpkNn^C1`&RJc5s|iWin~P|<dpe2Ut}0KW<bRGwaU)Y40e3-Y^hFx7A^xNgLlYodDs=s7wIme>TB|zIeb=Zdev0G80Pyfb;eRPHt2POb)c7=FRi50kvQ_=UGqX_z&sfwZ86(y@HQZV(OI&i;9Gj~}gSNO1nv$9Lcsc`9Fl_pbChz(L4>VKnby8gT#k)D#Ia=e@Q0xrOGdAl~iFuiW=Q&3h(Ucz;k+0xRgf7s76%b@0%?E%s{{(y&`pz(zR5GNJOa8^`UsgeemyE+7Z<<S}d{gU)jqb_oo+<Ys&<<rgssn`+$maMs*>^K#_YcYaDRC3EI_L?K-W)suoeN@Ox~w*mb6v2PB-HHZ8x@vNhC4qcThS2vFt61vYUb7x)I`sXHh$$8c<0juLQ1y!<aGm6tNOT|l%Ti{`jU$y7OY@<OB$%gpvr0@N6g(dz9Q=Us4afXF~^Y72J{^N7ijVx0i}%PB?<qsJEa9BWwSNaSzWj##|Kgoa6w<98}5pq8!sXaU)c)6evK?qWQ(c5<v;hK(rmObU@6VM5-Q*!a5TerygcqIiL>mDne))-7LhT-%A8sm%HOg-^*+%Qgd7DoVJni#tAUE2_kcOu0U_Bhm%qDk0w=}rT6nIG%Whde(*!L>DfFofC~IEsbFA+4+T&;Y26P$hL1x(4ToYMA@1C3Sh73VfG5GI^R-?eGFO6WvXU;d;@_tdMlk~3zOgCtesx|u9_ah*~h5cY1R@zW`>3DKvp6YEp=>XFsE}ahDC5PSHf;Z9`pxhtas2i3Qq^gS{J1ILw=T?IUF@GnwO&3HWz#2Eu00000vTB}H{a#Lj00G4Y_!R&Esqqg~vBYQl0ssI200dcD', 'residual5120'], 'rmsnorm5120': ['f7d1de5ad332c7e1d9f595ad8eaeb0cde46ad74427344d59a4d57734082e329f', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0xCSs$Bp-kwt`PJ&CWlzL$xU;@1fJvvaGl&TT-6>*73pP1TC8w7YEtPgrm*w@BUl#tTT?H&_nWRWGR4S$;F3`RS=Sa5*ONC=0HErS0O4apgI%j7nU@K4y3JEpB1F%(ukpXRZP+zP6dTJe{8VTpmzhCOyqZbkR-ISmLqBgzd;OzAi~iGu7CA;9S-!X=qmV16_(hs>EUN;f#NFfw%asT}<;DtB3~$GT8kMXKRI{e8-E|kZfoc+9;k;4pSVBE`(|}lbwy}fuR+aX72OBm?ZfKi|=KB)FTgTLJi@6ww>II57AD141x*Ye7^6c`Gol^N;<>6S^fR%<FCv|q`1{<yApE_`2eJ7=Nk(IZ4w}L>g@gD^QIH2+HaI#8?HH&>bz@Z1Ir-Ca3B?Adq|cdlWgyd$Ejc+_wJvN_+agVprvdNRTBQE^1XjrCUr5-GJ%9iv&>3r9$Al5o5oLT;AgY7M|9bcN?$zZaG#0TiHxm$r|kC-0K(qmYG6_;X*{dAnM&q@-Nsz}%-M0E#=zd;1b~b-D_LRsF_}8`!cq;p=0bd5*Px|)dOIqprqABVm0hzOMc1N(qa$XglJj>08V*10GooN=s~2V2>DmJ4dS+TPh%tJ~-7>CPIKJXN@ifD}URyap$qx<Fwcr`0BHO{$C?-Ia%yz0wiiQL<-p{mdy!RiK_LqPg3Dg6@nG8NCL(#ea4Cta#9z!pou0K{qd|?%a&(VoZOKe&Btnii{-4^!{1800G@m(S5paP7f-TT&)<JGg&S_#6AVeKnJ|LpAq8FviytO)VpI#U@))E;(HPA$RSW6^pT`D}+vhCHPVG!(rFc>4s$Ti8bby*Qp3;MjlF<H{U`a$kUv+cac{FY@r{9P+b@dsd~3C>!B1Szm5gk;oK&=`+oi2+dkVKPzD!JADvn$-~8fP&LSSW(QVE)F3XV3G?xd*xJ5Eq5pwL;o2<O78LoJYP@szns%EH1b5TERRwRq3LTF`2p*{(Ws3{sLZw%rZ9QDzDC*_29m)2cJ4p@63exJ&HufXF&$IL#FBdw&_7>{c0UFGc;)%B=lk!G}BIl#zByvUa-dm?waP2wPTDuUp?IxsD)>CztceX?9NHNi{61S^L+4)op6i`W+(2Z(Bi=w+VuQAh#VVm@dVy+SOT@qcIr%#Ax<R69I@283xu<eXU@m`ccMkL<8Qqi`@9EPs$^hSC6z5oCKug)g)A-?V*00G7a*cSi*=h00}vBYQl0ssI200dcD', 'rmsnorm5120'], 'step_advance': ['2f688c9f6f2f7af751d4976b6bf748f7b15fd4d4ca1d8d90c43fe228363b975c', '{Wp48S^xk9=GL@E0stWa8~^|S5YJf5;0cEUx?KQ2kwt`PJ&CWlzL$xU;@1fJvvaNi)}49P3&!+|U{%5Swk96Wi!r+Pe3shoROe1axZgX)X&f^72j8n7>@k2_OI)#?<4)!f;Ppj&qeV|1shG!b+Ar=;1*nldmMT>6Zi5Fkc4}l=br9pJF*?!8)+IO4{L7A6+vX--GKcOn6%gfn8nWLh2<^2I)vhK#de82A={U8;r)h5xTc%v<mDv-`2f6OrlDSxusb{(NW+O^xKf5_@z00kh*09<?27^+mK>U9#$;}JufIC-9EIC^X<{62l7aAJv$x*Et7r6WM>=m8hl%XFs3B38q)0zG=7BAB`6mXj09XuWIze7HHwkkTgc&u}_0=QPd3CPN_WM`rBG0hk!)pmL`$)gGaTl`Gx3<~Wi-=Cl99I36L2)GA!`bG*|NtS7+!@4X{)esub-Q-NdP*9UP+PXNF%Y=<@VHSt}i2=B@rkVG~S%JOEF8s`$Tku>Gc{phz*Kx<q?B*OT&=QM4`K(LWTJQS?fo8nv2WQ_4{#~W4ywVElmrJz`D*J$16XzYSqQ%<9W~^X(WBiJ}-;EhzQlsB)Ftpn>pQ?Pvl!^65{IW3cJ35~u>~h69F>-9E2ylM~$1zQcl;<(joIp5yg%s`VnRlpAuVr6tJ_xaN+l6rL;$iqdpUYuR4y~X*nQV?+O))fu`xjt<eMwRY#5-zb&lCjrXk+85w0x3ph@72%up*g%Y4YI<JE=8XGyqn6<av1?96EPqLO3rRn|f1rsq>jmJDS_D=h)%fpWX0)W0s6yQ&Yp^Vh8yRPvWP4^9ns*S`2LHMHK@myuNm_Jm4@G?!%|1P(<D>u}|n)$V7l^Qsux~xr$aAlGNPh9uLe81b$uD{M9;9XJw4L@RH`<ecq^bl$}>W8ZLo3TL1t6`YcW*x{R5L00Gtoh!X$+VkckuvBYQl0ssI200dcD', 'step_advance']}
PINS = {'config.json': '74227dd615bf1ea975aa676bdf355a0379858c12f394b5365cd9dfa5fc2c70bc', 'generation_config.json': 'e70c136c1b78ddc1fb0905bac8e733a4dc448d4f852a5dd75143fffc70be550e', 'layers-0.safetensors': '07f700e293baeaf3cd4240c3df1a948c4403f16961ea7979e86c8d6a9f8fd466', 'layers-1.safetensors': '35840b5d452c6e438d000e5c1d8d1bc793d257394404689b8f9424749eee8edc', 'layers-10.safetensors': 'ab5fbc076ccd6514aba3ab67a0ac1d6701ad395d40cccc0086cf0284ef5d68c9', 'layers-11.safetensors': '076b4ba44e9311c8fb8fdc0045f8ce9fd0c75584ade4e95510056b7db4b7ec61', 'layers-12.safetensors': '86d8ec0b8fc8e3ffbdfd667b97050533ddf5a4d273b4fe1190a4335542c52829', 'layers-13.safetensors': '71dd986134f4338a7b8290ed24993ad34a0f77b76a4cc060fe6403e36dcdda5b', 'layers-14.safetensors': '95b285915cba994917b527030874227382ea3421dc7f47d804c0ca5851f039fb', 'layers-15.safetensors': '1e87d61e77d2b802f796ab8a049b1119648c9b70d2ba1067f456e5a04449cfc3', 'layers-16.safetensors': '8bcdbf4e2c7a8dda3043c4453a476b30a582d58aabfaa49b2829a8b66a664acb', 'layers-17.safetensors': '571cea44717878cc8cbbfbd544acfe2d155f5b963fbf5dc67b3fa96afe840a1b', 'layers-18.safetensors': 'd8700627ca2267fb7beb5d398d6a659a9bfeeb2af76f10e6827b1e4359d59286', 'layers-19.safetensors': '2b24cfb752bbed959c614d7fd85412ee27ab2ac1f47deef5d09d0592781400e4', 'layers-2.safetensors': '32e63c6455ebfa10b4c36af2878eefcb6f8ccf8e947a62575444dc412c38ac1a', 'layers-20.safetensors': '52fd00c68d4f1df96ba701290c04237257ebb832879bb0b6a629525809d84a64', 'layers-21.safetensors': 'e3c29dd949808c13116d853ce4b0f96cb1238fc0cb6999ab76735deef6bda77a', 'layers-22.safetensors': '63446546e3e09c2394fc51855f4e390cb47f896bb8b744f3a210c3159a3ccaf2', 'layers-23.safetensors': '4166ed11d0329985f9813ba6a70474ea9f5aeff3d97db3d7b2e81185bd41a996', 'layers-24.safetensors': '720bdcfe12b6627bed29feda9c96256e15c20602704669d05097668a9f03dd45', 'layers-25.safetensors': '1b188e7e4e8ae6f5d753c597f61d86c1593495de4307c273d8dda9946ec48bb4', 'layers-26.safetensors': 'ad8c3e3d4b79dfedad674318ee4b150b2cd78b56747c7c8d88a65818109a545d', 'layers-27.safetensors': '8d63f461430045960f27a22abf685bfc7445fffbb24764e4a7fa993ba7edac08', 'layers-28.safetensors': 'f78557cda66107ce25f8c5ecde2f83da874b3bf7c50381e062e14e7294a5b64d', 'layers-29.safetensors': '09f264d6fdddab0fb5ecce18034a9a01944d15118147c97058fba101a60f8af1', 'layers-3.safetensors': '302f9af90bb683a8be9e96d124b470a2eddee6612c95c39a8e93f26eb654563d', 'layers-30.safetensors': '54afe4fc7262ee597d4d9b80d2d6fe8ae501846ff124334b575bed4c6850ed97', 'layers-31.safetensors': '2779338203d0715ca323ac0b7fdbb0d450ce2bd1694be395a211a02ade3f34d9', 'layers-32.safetensors': 'f4af8893594458b6cdb074ef20f9accb708361fe904012465990d09e74994509', 'layers-33.safetensors': '8f038505b9fc7d0b31ca976c728b56028ec28390a15ca0410f00df18d3abc1a4', 'layers-34.safetensors': '0b28f43cc4d3ae50e37eb3c2ce12a6e181b1c7586a27d5a05c6a3367f08286c9', 'layers-35.safetensors': '535b61b9eabbcda5de20e21d2d46fb52528cc9c1f8fac38920382ea2f1030837', 'layers-36.safetensors': '2babd209cafbe12a6e375ff6e7a1029f36ee8226f2a9babf6646630f31dd3fb8', 'layers-37.safetensors': '651cae579808983fefec954db6e2ac8c3f98bfb038ff1d50aef0505ba7394e65', 'layers-38.safetensors': '1c60932dec650cc7679121eaa4d90b8d10a600bf58e23b0784588a339469dd0a', 'layers-39.safetensors': 'b0c7df4d51b99637ff4ea35eebf7eb134db592eb943e3ccde921729f33949058', 'layers-4.safetensors': 'b7f367125cdb4b3c3920d1d3ed1ba0d73e464c3e3a92dbd1c195658cb9200afd', 'layers-40.safetensors': '6908f1ab1a3d7828a566099ecf393582bec988d0f82f6141848942d1494b0321', 'layers-41.safetensors': '21ee5d9842074888bd9fdffa875d1f29f8c77f1f5ccbb8f53becb188e1749caa', 'layers-42.safetensors': '565379d4291c06cdf9a4f66d5d21385848a1e5ab17b55fea6c1c8e544f8498f0', 'layers-43.safetensors': '4bb8c0a4fadda1f1d66ef6f0dde5a5a94001d04af1842e42009833aff70bf416', 'layers-44.safetensors': '14339304cd520a8673f179cb8352c36fbebe184f15309aee2a79afd2d4476fef', 'layers-45.safetensors': '7a076aca542f937cc87dec92ab49fd782eae234642b40bc706a6108b3dff2c2a', 'layers-46.safetensors': 'd82d472cfc4792012934467b90c5e0242df4867a430dd651d13cdee72b7c6645', 'layers-47.safetensors': 'a83fc757fb11bc50ed3a0c9998b2b2f55c3b6a07598ed458bdbece4285ffaf1f', 'layers-48.safetensors': 'f6aa126d006c7d976c20b1330c118b42cf3bbe8a7d216bb14f2240d5c49bc72f', 'layers-49.safetensors': '7ed54c375407c2baec8cfabe8336f8d3782246848298bb232ac2582113676c69', 'layers-5.safetensors': 'ebbc2c4bd2b98877caafa7073b6ed732a0284eb82269cf6d21710e245af5837a', 'layers-50.safetensors': '73825e1f056c3de53276d3c65743e62b67bf3ca082cf7077ecba1ffef18e9bf1', 'layers-51.safetensors': 'b6abd8b62b5c4b7beca8cdccd306065be2192ef42491c587ca019d971ed86a1f', 'layers-52.safetensors': '6251d51e6fbec6f463ca875fcbe852e07c5025145affe9af053a04fbdc37288f', 'layers-53.safetensors': 'a9f2f43b4978bba2f755c6d2eb39f8561965bc3c1b2fd1073bb363aff11a9b8c', 'layers-54.safetensors': 'f0246c9974a4b1207f8f5d05a09c54c50ea61fbfd2dc6480d2b76d3647ece292', 'layers-55.safetensors': '649c400495616cf888b7c52e538113610a36265c531d84bff484f8149c157405', 'layers-56.safetensors': 'eb0a8139a36138639a37219c158b9415412b68d316235061a72e57da5509c188', 'layers-57.safetensors': 'd7616ad33f9256342573ff85b3f2a0e368dd120257c0c7158564587036119d95', 'layers-58.safetensors': 'a8dff0e37d0e3903cc29711b935c2865ccd38bd930e7487ae2f4bedbd18ff185', 'layers-59.safetensors': '573ed65fd455ec9bd811e95946ea422e08ac36860fdff6968a6d108263a54175', 'layers-6.safetensors': '2fea2aaa61d566ba8af27ee89d29d9ee9f1c7f6fbe692772d9ba61fc45109ef6', 'layers-60.safetensors': '9a19c30b190bf552eb424af16103f610bcd944fb276b3275eb7c73849799b7de', 'layers-61.safetensors': 'ff744debd4dd0eef450ed24473df57680db404914302e7147a3b72154131f4a0', 'layers-62.safetensors': 'd9b3b9e472f78bcadf62c446084833bb549faff9e730b21219f1f80d583eff23', 'layers-63.safetensors': '59ba4a3af5e6bc2008c2d6b5d9be8eeaf255cddc0aaf8a0d9583b496bb2e3ae0', 'layers-7.safetensors': 'f2e0137e878016a7afdb2314972e0cbbe2461a67b00eb1d691b4de8ea2665da8', 'layers-8.safetensors': '1721b7bcd730891c224b70a7b6147e44a574a2d6c4d924760acf97728249c92c', 'layers-9.safetensors': '0a21e07065b5bb04adc339300dea1872cc48ab8eab3b02df092f7cbc67c8d6f6', 'model.safetensors.index.json': 'f0838c766951bdfe76d6afbdb2771a8f67aaa2231dedb3d33cebd817729843a2', 'outside.safetensors': 'ddff1d6665a2b39f2612fce0ef955e2436724c565bfbcbc127c7ffd078b698ff'}
GOLD = {'prompt_ids': [248045, 846, 198, 7734, 264, 351, 709, 421, 4523, 279, 7875, 314, 1330, 52883, 13, 248046, 198, 248045, 74455, 198, 248068, 271, 248069, 271], 'generated_ids': [71093, 66, 198, 390, 1866, 1494, 264, 11, 514, 292, 8, 313, 198, 262, 460, 318, 64, 835, 292, 8, 907, 264, 535, 292], 'top5': [[[71093, 23.317401885986328], [8160, 20.65513038635254], [2, 19.24697494506836], [760, 16.893421173095703], [40, 16.54787254333496]], [[66, 25.552215576171875], [198, 16.269433975219727], [34, 15.795976638793945], [10504, 15.427840232849121], [11197, 12.803357124328613]], [[198, 25.711669921875], [271, 15.203243255615234], [1032, 14.847509384155273], [514, 14.402992248535156], [390, 14.395952224731445]], [[390, 30.04957389831543], [1032, 25.954788208007812], [3537, 22.374156951904297], [1911, 20.336767196655273], [1389, 19.070329666137695]], [[1866, 27.237834930419922], [7875, 23.494924545288086], [514, 19.317373275756836], [6826, 19.08346939086914], [7526, 18.804264068603516]], [[1494, 24.473876953125], [3456, 22.7589054107666], [3906, 21.32562828063965], [22517, 19.032346725463867], [2654, 17.598129272460938]], [[264, 29.835716247558594], [830, 20.790369033813477], [585, 16.620248794555664], [11, 16.196826934814453], [1572, 15.429924011230469]], [[11, 26.28640365600586], [8, 13.289999008178711], [9579, 13.25779914855957], [1494, 12.254295349121094], [514, 12.211318969726562]], [[514, 28.971960067749023], [292, 16.95057487487793], [713, 15.528327941894531], [1248, 15.443767547607422], [198, 14.397457122802734]], [[292, 27.26201057434082], [264, 15.754175186157227], [272, 14.55998706817627], [8, 12.938213348388672], [343, 12.88210678100586]], [[8, 26.66093635559082], [1174, 17.31379508972168], [5908, 14.608078002929688], [11, 13.509659767150879], [198, 12.859498023986816]], [[313, 26.29653549194336], [198, 21.19902801513672], [695, 14.95692253112793], [460, 13.500253677368164], [271, 11.55713939666748]], [[198, 23.275623321533203], [460, 13.959972381591797], [317, 12.277848243713379], [262, 11.036907196044922], [271, 10.608769416809082]], [[262, 27.755077362060547], [220, 15.873917579650879], [460, 15.344642639160156], [256, 15.254963874816895], [827, 14.41589641571045]], [[460, 28.363656997680664], [413, 23.624923706054688], [318, 16.96184539794922], [514, 16.812294006347656], [264, 16.32174301147461]], [[318, 25.871816635131836], [264, 25.12784194946289], [2784, 13.386415481567383], [835, 12.829448699951172], [292, 12.81915283203125]], [[64, 33.14234924316406], [390, 17.77625274658203], [65, 17.22248649597168], [87, 15.74583911895752], [198, 15.743099212646484]], [[835, 30.18769073486328], [2518, 23.545799255371094], [361, 19.410917282104492], [8, 14.581828117370605], [478, 14.48072338104248]], [[292, 27.102005004882812], [220, 14.388344764709473], [417, 13.271217346191406], [264, 13.225276947021484], [8, 12.754480361938477]], [[8, 29.864059448242188], [907, 18.219181060791016], [11504, 17.216129302978516], [847, 14.829612731933594], [60, 13.985965728759766]], [[907, 33.142181396484375], [198, 18.168197631835938], [535, 17.340913772583008], [264, 16.761648178100586], [26378, 15.987364768981934]], [[264, 28.735010147094727], [292, 17.341135025024414], [318, 16.440004348754883], [220, 14.874212265014648], [198, 14.214522361755371]], [[535, 26.687559127807617], [198, 14.383487701416016], [25, 12.860763549804688], [292, 12.292506217956543], [478, 11.972315788269043]], [[292, 30.048683166503906], [318, 16.205198287963867], [417, 14.845285415649414], [198, 14.738409042358398], [264, 14.456117630004883]]]}
SOURCE = 'fp8 block source 9d6fc207445a851ea8fa9f545f9df34012b60224; omc 2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f; replay source edda0f13dfbe759fa9d92d0bcfa5e36eae3587cc; replay gate/provenance receipt sha256 c5665275bae7907dda374dac67c834f07e714cd0e15bf34fad00cdf618e2de3b; all objects pinned individually in OBJ; unlanded experiment'
ORACLE = {'status': 'INTERRUPTED; full 24-token CPU oracle NOT_RUN to completion', 'source': '/home/drakestapleton/handoffs/hive/amdserve/notebook-probe/real1/oracle.log', 'source_sha256': 'b642fc70553d2fdb471f09adac9cfd634934e8d1e4525363c5352049c4221ccd', 'generated_steps_recorded': 9, 'last_logged_seconds': 2424.4762779109988, 'peak_rss_kib': 'NOT_RECORDED before interruption', 'abi_vs_fp32_top5': 'NOT_RECORDED before interruption', 'modes': {'fp32': {'ids': [71093, 66, 198, 390, 1866, 1494, 264, 11, 514], 'matches_in_recorded_prefix': 9, 'first_divergence_zero_based': None}, 'abi': {'ids': [71093, 66, 198, 390, 1866, 1494, 264, 11, 514], 'matches_in_recorded_prefix': 9, 'first_divergence_zero_based': None}, 'no_one': {'ids': [158949, 12729, 158949, 158949, 158949, 158949, 158949, 158949, 158949], 'matches_in_recorded_prefix': 0, 'first_divergence_zero_based': 0}, 'swap_qg': {'ids': [17, 17, 17, 17, 17, 17, 17, 17, 17], 'matches_in_recorded_prefix': 0, 'first_divergence_zero_based': 0}, 'row_scales': {'ids': [71093, 66, 198, 390, 1866, 1494, 264, 11, 514], 'matches_in_recorded_prefix': 9, 'first_divergence_zero_based': None}}}
READFIRST = {'input': [2881486848, 2881486849, 2881486850, 2881486851, 2881486852, 2881486853, 2881486854, 2881486855, 2881486856, 2881486857, 2881486858, 2881486859, 2881486860, 2881486861, 2881486862, 2881486863, 2881486864, 2881486865, 2881486866, 2881486867, 2881486868, 2881486869, 2881486870, 2881486871, 2881486872, 2881486873, 2881486874, 2881486875, 2881486876, 2881486877, 2881486878, 2881486879, 2881486880, 2881486881, 2881486882, 2881486883, 2881486884, 2881486885, 2881486886, 2881486887, 2881486888, 2881486889, 2881486890, 2881486891, 2881486892, 2881486893, 2881486894, 2881486895, 2881486896, 2881486897, 2881486898, 2881486899, 2881486900, 2881486901, 2881486902, 2881486903, 2881486904, 2881486905, 2881486906, 2881486907, 2881486908, 2881486909, 2881486910, 2881486911], 'rows': [{'mask': 0, 'expected': 2881486848}, {'mask': 1, 'expected': 2881486848}, {'mask': 2, 'expected': 2881486849}, {'mask': 9223372036854775808, 'expected': 2881486911}, {'mask': 9223372036854775816, 'expected': 2881486851}, {'mask': 18446744073709551615, 'expected': 2881486848}]}
REV='017b9c7af6b5689d5dd426a76e0bc077eb5ca20a'
ROOT=Path(os.environ.get('AMDSERVE_WEIGHTS','/tmp/qwen3.8-27b-fp8'))
OUT=Path(os.environ.get('AMDSERVE_OUTPUT','amdserve-real2.txt'))
STATE=Path(str(OUT)+'.state');MARK=Path(str(OUT)+'.mark')
GROUP=os.environ.get('AMDSERVE_GROUP','')
PFX='model.language_model.'
def say(s):
    print(s,flush=True)
    with OUT.open('a') as f:f.write(s+'\n')
def digest(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda:f.read(8<<20),b''):h.update(chunk)
    return h.hexdigest()
def prepare():
    ROOT.mkdir(parents=True,exist_ok=True)
    for name,sha in PINS.items():
        p=ROOT/name
        if not p.exists():
            MARK.write_text('download '+name)
            tmp=Path(str(p)+'.partial')
            with urllib.request.urlopen('https://huggingface.co/Qwen/Qwen3.8-27B-FP8/resolve/'+REV+'/'+name) as response,tmp.open('wb') as f:
                while True:
                    b=response.read(8<<20)
                    if not b:break
                    f.write(b)
            if digest(tmp)!=sha:raise RuntimeError('download SHA256 mismatch '+name)
            tmp.replace(p)
        if digest(p)!=sha:raise RuntimeError('SHA256 mismatch '+name)
    say('CHECKPOINT SHA256 verified '+str(len(PINS))+' files at '+REV+'; shared outside shard includes unused visual bytes; no visual tensors loaded')

def parent():
    OUT.write_text('');STATE.write_text('');groups=['readfirst','controls','row-scales','omega-enqueue','omega-graph','reference'];faults=[]
    say('REAL2 '+SOURCE+'; CONTROLS first; each phase is a fresh child')
    say('ORACLE CPU differences (reported, not gating) '+json.dumps(ORACLE))
    try:
        for group in groups:
            MARK.write_text('starting '+group)
            with open(str(OUT)+'.stderr-'+group,'w') as err:
                rc=subprocess.run([sys.executable,str(Path(__file__).resolve())],env=dict(os.environ,AMDSERVE_GROUP=group),stderr=err).returncode
            if rc: faults.append([group,rc,MARK.read_text()]);say('FAULT '+json.dumps(faults[-1]))
            if rc and group=='readfirst':break
    finally:
        states=[json.loads(l) for l in STATE.read_text().splitlines() if l.strip()]
        by={s['group']:s for s in states}
        ok=all(by.get(g,{}).get('ok',False) for g in ['readfirst','controls','omega-enqueue','omega-graph']) and not faults
        comparison={}
        for group,label in [('omega-enqueue','OMEGA Python enqueue'),('omega-graph','OMEGA graph replay'),('reference','REFERENCE AMD library, not Omega')]:
            state=by.get(group,{})
            row=state.get('result',state)
            comparison[label]={'decode_ms_median':row.get('decode_ms_median'),'ids_match':row.get('ids_match'),'status':row.get('status','EXERCISED' if 'decode_ms' in row else 'NOT_RUN')}
        say('COMPARISON same-session synchronized wall time '+json.dumps(comparison))
        say('NOT_RUN hardware qualification outside this run; production serving; non-greedy sampling; MTP; image/video input')
        say('RESULT '+('PASS' if ok else 'FAIL_OR_INCOMPLETE')+' '+json.dumps(states))
    return 0 if ok else 1

def check_bounds(name,args):
    # Byte requirements of the fixed Qwen kernel ABIs; dynamic sizes derive from arguments.
    h,kh,d,nv,kd,ch=5120,4,256,48,128,10240
    if name=='fp8gemv_b128f':
        m,k=args[-2:];sizes=[m*k,4*k,2*((m+127)//128)*((k+127)//128),4*m]
    elif name=='bf16gemv2':
        m,k=args[-2:];sizes=[2*m*k,4*k,4*m]
    elif name=='rmsnorm5120':sizes=[4*h*args[-1],4*h,4*h*args[-1]]
    elif name=='embed5120_step':sizes=[2*h*args[-1],4*h,4]
    elif name=='residual5120':sizes=[4*h]*3
    elif name=='mlpsilu':sizes=[4*args[-1]]*3
    elif name=='gdnparams':sizes=[4*nv]*6
    elif name=='gdnconv4_step':sizes=[4*ch,8*ch,8*ch,8*ch,4*ch,4]
    elif name=='gdnqknorm':sizes=[4*2*16*kd]*2
    elif name=='gdnstate_step':sizes=[4*2*16*kd,4*nv*kd,4*nv*kd*kd,4*nv*kd*kd,4*nv*kd,4*nv,4*nv,4]
    elif name=='gdnrmsgate':sizes=[4*nv*kd,4*kd,4*nv*kd,4*nv*kd]
    elif name=='attn256_prep_step':
        cap=args[-1]
        sizes=[4*24*2*d,4*kh*d,4*kh*d,4*d,4*d,4*cap*64,4*24*d,2*kh*cap*d,2*kh*cap*d,4]
    elif name in ('attn256_part_step','attn256_merge_step'):
        cap=args[-1]
        sizes=[4*24*d,2*kh*cap*d,2*kh*cap*d,24*((cap+63)//64)*1040,4*24*d,4]
    elif name=='attn256_gate':sizes=[4*24*2*d,4*24*d,4*24*d]
    elif name=='argmax_part':sizes=[4*248320,8*((248320+63)//64)]
    elif name=='argmax_final':sizes=[8*((248320+63)//64),4]
    elif name=='step_advance':sizes=[4]
    elif name in ('readfirst_probe','readfirst_probe-zero'):sizes=[256,4]
    else:raise ValueError('no bounds contract for '+name)
    for i,(tensor,needed) in enumerate(zip(args,sizes)):
        actual=tensor.numel()*tensor.element_size()
        if actual<needed:raise ValueError('%s arg%d has %d bytes, needs %d'%(name,i,actual,needed))

class Hip:
    def __init__(self,torch):
        self.torch=torch;torch.cuda.init()
        libs=[l.split()[-1] for l in open('/proc/self/maps') if 'libamdhip64' in l]
        self.lib=ctypes.CDLL(libs[0] if libs else 'libamdhip64.so');self.functions={};self.modules=[]
        self.stream=ctypes.c_void_p();self.check(self.lib.hipStreamCreate(ctypes.byref(self.stream)),'stream create')
        for name,(sha,data,symbol) in OBJ.items():
            raw=lzma.decompress(base64.b85decode(data));assert hashlib.sha256(raw).hexdigest()==sha
            mod,fn=ctypes.c_void_p(),ctypes.c_void_p()
            self.check(self.lib.hipModuleLoadData(ctypes.byref(mod),ctypes.create_string_buffer(raw,len(raw))),'load '+name)
            self.check(self.lib.hipModuleGetFunction(ctypes.byref(fn),mod,symbol.encode()),'function '+name)
            self.modules.append(mod);self.functions[name]=fn
    def check(self,rc,name):
        if rc:raise RuntimeError(name+' rc='+str(rc))
    def launch(self,name,gx,gy,*args):
        check_bounds(name,args)
        MARK.write_text(name+' group='+GROUP)
        vals=[ctypes.c_uint32(a) if isinstance(a,int) else ctypes.c_void_p(a.data_ptr()) for a in args]
        arr=(ctypes.c_void_p*len(vals))(*[ctypes.cast(ctypes.byref(v),ctypes.c_void_p) for v in vals])
        self.check(self.lib.hipModuleLaunchKernel(self.functions[name],gx,gy,1,64,1,1,0,self.stream,arr,None),'launch '+name)
    def sync(self):self.check(self.lib.hipStreamSynchronize(self.stream),'stream synchronize')
    def capture(self,emit):
        self.check(self.lib.hipStreamBeginCapture(self.stream,0),'begin graph capture')
        graph=ctypes.c_void_p()
        try:emit()
        except BaseException:
            self.lib.hipStreamEndCapture(self.stream,ctypes.byref(graph))
            if graph.value:self.lib.hipGraphDestroy(graph)
            raise
        self.check(self.lib.hipStreamEndCapture(self.stream,ctypes.byref(graph)),'end graph capture')
        executable=ctypes.c_void_p()
        try:self.check(self.lib.hipGraphInstantiate(ctypes.byref(executable),graph,None,None,0),'instantiate graph')
        finally:self.check(self.lib.hipGraphDestroy(graph),'destroy captured graph')
        return executable
    def replay(self,executable):
        self.check(self.lib.hipGraphLaunch(executable,self.stream),'launch graph')
    def release_graph(self,executable):
        self.check(self.lib.hipGraphExecDestroy(executable),'destroy graph executable')

def readfirst_probe(torch):
    hip=Hip(torch);inp=torch.tensor(READFIRST['input'],device='cuda',dtype=torch.uint32)
    out=torch.zeros(1,device='cuda',dtype=torch.uint32);rows=[]
    for case in READFIRST['rows']:
        mask,expected=case['mask'],case['expected']
        lo,hi=mask&0xffffffff,mask>>32
        out.fill_(0xdeadbeef);torch.cuda.synchronize()
        hip.launch('readfirst_probe',1,1,inp,out,lo,hi);hip.sync();actual=int(out.item())
        out.fill_(0xdeadbeef);torch.cuda.synchronize()
        hip.launch('readfirst_probe-zero',1,1,inp,out,lo,hi);hip.sync();negative=int(out.item())
        rows.append({'mask':mask,'expected':expected,'actual':actual,'negative':negative})
        if actual!=expected or negative!=0 or negative==expected:raise RuntimeError('readfirst semantic/control failure '+json.dumps(rows[-1]))
    say('CONTROLS readfirst positive bit-exact; zero-readfirst negative CAUGHT '+json.dumps(rows))
    return rows

class Card:
    def __init__(self,torch,hip,mode='omega'):
        from safetensors import safe_open
        self.t=torch;self.hip=hip;self.pos=0;self.cap=len(GOLD['prompt_ids'])+len(GOLD['generated_ids']);self.states={};self.weights={}
        self.graph=None;self.capture_ms=0.0
        config=json.load(open(ROOT/'config.json'))['text_config'];self.kinds=config['layer_types'];self.theta=config['rope_parameters']['rope_theta']
        assert config['hidden_size']==5120 and config['rms_norm_eps']==1e-6 and config['head_dim']==256
        assert config['rope_parameters']['partial_rotary_factor']==0.25
        index=json.load(open(ROOT/'model.safetensors.index.json'))['weight_map']
        names=[n for n in index if n=='lm_head.weight' or n.startswith(PFX) and '.mtp.' not in n]
        for file in sorted({index[n] for n in names}):
            MARK.write_text('load tensors '+file)
            with safe_open(str(ROOT/file),framework='pt',device='cpu') as f:
                for n in names:
                    if index[n]!=file:continue
                    w=f.get_tensor(n)
                    # Matrices and scale grids retain packed checkpoint types. Small vectors widen.
                    if w.ndim==1:w=w.float()
                    if n.endswith('conv1d.weight'):w=w.reshape(10240,4)
                    if mode=='controls' and (n==PFX+'norm.weight' or n.endswith(('input_layernorm.weight','post_attention_layernorm.weight','self_attn.q_norm.weight','self_attn.k_norm.weight'))):w=w-1
                    if mode=='row-scales' and n.endswith('weight_scale_inv'):w=w[:,0:1].expand_as(w).contiguous()
                    self.weights[n]=w.to('cuda')
        self.h=self.empty(5120);self.h2=self.empty(5120);self.xn=self.empty(5120);self.pj=self.empty(5120)
        self.qg=self.empty(12288);self.kr=self.empty(1024);self.vr=self.empty(1024);self.q=self.empty(6144);self.ao=self.empty(6144);self.go=self.empty(6144)
        angles=torch.arange(self.cap,dtype=torch.float64).unsqueeze(1)/torch.pow(torch.tensor(self.theta,dtype=torch.float64),torch.arange(32,dtype=torch.float64)*2/64)
        self.cs=torch.cat((angles.cos(),angles.sin()),dim=1).float().to('cuda')
        self.parts=self.empty(24*((self.cap+63)//64)*1040//4)
        self.qkv=self.empty(10240);self.z=self.empty(6144);self.a=self.empty(48);self.b=self.empty(48);self.dec=self.empty(48);self.beta=self.empty(48)
        self.co=self.empty(10240);self.qkn=self.empty(4096);self.core=self.empty(6144);self.gout=self.empty(6144)
        self.g=self.empty(17408);self.u=self.empty(17408);self.act=self.empty(17408);self.logits=self.empty(248320)
        self.argmax_parts=self.empty(3880*2);self.tok=torch.zeros(1,dtype=torch.int32,device='cuda')
        self.position=torch.zeros(1,dtype=torch.int32,device='cuda')
        for l,kind in enumerate(self.kinds):
            if kind=='full_attention':self.states[l]=[self.empty((4,self.cap,256),torch.bfloat16),self.empty((4,self.cap,256),torch.bfloat16)]
            else:self.states[l]=[self.empty((10240,4),torch.bfloat16),self.empty((10240,4),torch.bfloat16),self.empty((48,128,128)),self.empty((48,128,128))]
        torch.cuda.synchronize()
    def empty(self,shape,dtype=None):return self.t.zeros(shape,dtype=dtype or self.t.float32,device='cuda')
    def gv(self,name,x,y):
        w=self.weights[name+'.weight'];m,k=w.shape
        assert x.numel()>=k and y.numel()>=m
        if w.dtype==self.t.bfloat16:self.hip.launch('bf16gemv2',m,1,w,x,y,m,k)
        else:
            s=self.weights[name+'.weight_scale_inv'];assert tuple(s.shape)==((m+127)//128,(k+127)//128)
            self.hip.launch('fp8gemv_b128f',m,1,w,x,s,y,m,k)
    def forward(self,token=None,graph=False):
        if self.pos>=self.cap:raise ValueError('step would exceed allocated cache/RoPE capacity')
        if token is not None:
            if not 0<=token<248320:raise ValueError('prompt token outside vocabulary')
            self.tok.fill_(token);self.t.cuda.synchronize()
        if graph and self.graph is None:
            MARK.write_text('capturing fixed device-stepped graph')
            begin=time.perf_counter();self.graph=self.hip.capture(self.emit);self.capture_ms=(time.perf_counter()-begin)*1000
            MARK.write_text('graph replay group='+GROUP)
        begin=time.perf_counter()
        if graph:self.hip.replay(self.graph)
        else:self.emit()
        self.hip.sync();elapsed=(time.perf_counter()-begin)*1000;self.pos+=1
        return self.logits.cpu(),int(self.tok.item()),elapsed
    def emit(self):
        run=self.hip.launch
        run('embed5120_step',80,1,self.weights[PFX+'embed_tokens.weight'],self.h,self.tok,248320)
        for l,kind in enumerate(self.kinds):
            p=PFX+f'layers.{l}.';w=self.weights;st=self.states[l]
            run('rmsnorm5120',1,1,self.h,w[p+'input_layernorm.weight'],self.xn,1)
            if kind=='linear_attention':
                a=p+'linear_attn.'
                self.gv(a+'in_proj_qkv',self.xn,self.qkv);self.gv(a+'in_proj_z',self.xn,self.z)
                self.gv(a+'in_proj_a',self.xn,self.a);self.gv(a+'in_proj_b',self.xn,self.b)
                run('gdnparams',1,1,self.a,self.b,w[a+'A_log'],w[a+'dt_bias'],self.dec,self.beta)
                run('gdnconv4_step',160,1,self.qkv,w[a+'conv1d.weight'],st[0],st[1],self.co,self.position)
                run('gdnqknorm',32,1,self.co,self.qkn)
                run('gdnstate_step',3,16,self.qkn,self.co[4096:],st[2],st[3],self.core,self.dec,self.beta,self.position)
                run('gdnrmsgate',48,1,self.core,w[a+'norm.weight'],self.z,self.gout)
                self.gv(a+'out_proj',self.gout,self.pj)
            else:
                a=p+'self_attn.'
                self.gv(a+'q_proj',self.xn,self.qg);self.gv(a+'k_proj',self.xn,self.kr);self.gv(a+'v_proj',self.xn,self.vr)
                run('attn256_prep_step',24,1,self.qg,self.kr,self.vr,w[a+'q_norm.weight'],w[a+'k_norm.weight'],self.cs,self.q,st[0],st[1],self.position,self.cap)
                args=(self.q,st[0],st[1],self.parts,self.ao,self.position,self.cap)
                run('attn256_part_step',(self.cap+63)//64,24,*args);run('attn256_merge_step',1,24,*args)
                run('attn256_gate',96,1,self.qg,self.ao,self.go);self.gv(a+'o_proj',self.go,self.pj)
            run('residual5120',80,1,self.h,self.pj,self.h2)
            run('rmsnorm5120',1,1,self.h2,w[p+'post_attention_layernorm.weight'],self.xn,1)
            self.gv(p+'mlp.gate_proj',self.xn,self.g);self.gv(p+'mlp.up_proj',self.xn,self.u)
            run('mlpsilu',272,1,self.g,self.u,self.act,17408);self.gv(p+'mlp.down_proj',self.act,self.pj)
            run('residual5120',80,1,self.h2,self.pj,self.h)
        run('rmsnorm5120',1,1,self.h,self.weights[PFX+'norm.weight'],self.xn,1)
        self.gv('lm_head',self.xn,self.logits)
        run('argmax_part',3880,1,self.logits,self.argmax_parts);run('argmax_final',1,1,self.argmax_parts,self.tok)
        run('step_advance',1,1,self.position,self.cap)

def top5_difference(logits,expected):
    values,tokens=logits.topk(5);actual=list(zip(tokens.tolist(),values.tolist()))
    ranks={token:i for i,(token,value) in enumerate(actual)}
    known=dict(expected)
    return {'golden_entries':[{'token':token,'golden_rank':i,'actual_rank':ranks.get(token),'golden_logit':value,'actual_logit':float(logits[token]),'delta_actual_minus_golden':float(logits[token])-value} for i,(token,value) in enumerate(expected)],'actual_only':[{'token':token,'actual_rank':i,'actual_logit':value,'golden_logit':None,'reason':'not present in saved golden top5'} for i,(token,value) in enumerate(actual) if token not in known]}

def reference(torch):
    import transformers,safetensors,tempfile
    from transformers import AutoConfig,AutoModelForCausalLM
    outer=AutoConfig.from_pretrained(ROOT,local_files_only=True,trust_remote_code=False)
    config=outer.text_config
    config.quantization_config=dict(outer.quantization_config)
    index=json.loads((ROOT/'model.safetensors.index.json').read_text())
    # The checkpoint's list also names MoE modules (mlp.gate, mlp.shared_expert_gate) that this dense model lacks; transformers
    # matches entries by prefix, so 'mlp.gate' kept every mlp.gate_proj unconverted (FP8 weight in a BF16 Linear, card run 2026-11-13).
    # Keep only entries that name a module with tensors in this checkpoint.
    present=set(index['weight_map'])
    config.quantization_config['modules_to_not_convert']=[n.replace('model.language_model.','model.') for n in config.quantization_config.get('modules_to_not_convert',[]) if 'visual.' not in n and '.mtp.' not in n and any(k.startswith(n+'.') for k in present)]
    index['weight_map']={n:f for n,f in index['weight_map'].items() if n=='lm_head.weight' or n.startswith(PFX) and '.mtp.' not in n}
    # A generated metadata view avoids requesting the unused mtp shard or constructing vision.
    with tempfile.TemporaryDirectory(prefix='real1b-reference-') as td:
        view=Path(td)
        for filename in set(index['weight_map'].values()):(view/filename).symlink_to((ROOT/filename).resolve())
        (view/'model.safetensors.index.json').write_text(json.dumps(index))
        # transformers 5.x from_pretrained reads generation_config.json from the model directory (TypeError when absent, real1b card run);
        # the checkpoint ships it. Decoding below is a manual greedy loop, so its sampling fields are not used.
        if not (ROOT/'generation_config.json').is_file():raise RuntimeError('checkpoint generation_config.json missing at '+str(ROOT))
        (view/'generation_config.json').symlink_to((ROOT/'generation_config.json').resolve())
        model=AutoModelForCausalLM.from_pretrained(view,config=config,key_mapping={r'^model\.language_model\.':'model.'},local_files_only=True,trust_remote_code=False,torch_dtype=torch.bfloat16,device_map='cuda').eval()
    ids=[];top=[];details=[];times=[]
    tokens=torch.tensor([GOLD['prompt_ids']],device='cuda')
    mask=torch.ones_like(tokens);past=None;prefill_ms=None
    with torch.inference_mode():
        for i in range(len(GOLD['generated_ids'])):
            MARK.write_text('AMD library '+('prefill' if i==0 else 'decode '+str(i)))
            torch.cuda.synchronize();begin=time.perf_counter()
            output=model(input_ids=tokens,attention_mask=mask,past_key_values=past,use_cache=True)
            torch.cuda.synchronize();elapsed=(time.perf_counter()-begin)*1000
            if i==0:prefill_ms=elapsed
            else:times.append(elapsed)
            past=output.past_key_values;logits=output.logits[0,-1].float().cpu()
            token=int(logits.argmax());ids.append(token)
            values,indices=logits.topk(5);top.append(list(zip(indices.tolist(),values.tolist())))
            details.append(top5_difference(logits,GOLD['top5'][i]))
            tokens=torch.tensor([[token]],device='cuda')
            mask=torch.cat((mask,torch.ones_like(tokens)),dim=1)
    return {'status':'EXERCISED','ids':ids,'ids_match':sum(a==b for a,b in zip(ids,GOLD['generated_ids'])),'top5':top,'top5_differences':details,'prefill_ms':prefill_ms,'decode_ms':times,'decode_ms_median':statistics.median(times) if times else None,'timing':'batched prompt prefill, then cached one-token forward calls; synchronized wall time; no graph replay; token selection and host transfer excluded','torch':torch.__version__,'transformers':transformers.__version__,'safetensors':safetensors.__version__,'hip':torch.version.hip}

def measure(torch,mode):
    card=Card(torch,Hip(torch),mode);ids=[];top=[];dev=[];details=[];times=[];argmax_ok=True
    graph=mode!='omega-enqueue'
    try:
        for token in GOLD['prompt_ids']:logits,next_token,ms=card.forward(token)
        for i in range(len(GOLD['generated_ids'])):
            ids.append(next_token);argmax_ok &= next_token==int(logits.argmax())
            val,idx=logits.topk(5);top.append(list(zip(idx.tolist(),val.tolist())))
            dev.append(max(abs(float(logits[t])-v) for t,v in GOLD['top5'][i]))
            details.append(top5_difference(logits,GOLD['top5'][i]))
            if i+1<len(GOLD['generated_ids']):logits,next_token,ms=card.forward(graph=graph);times.append(ms)
        matches=sum(a==b for a,b in zip(ids,GOLD['generated_ids']))
        first=next((i for i,(a,b) in enumerate(zip(ids,GOLD['generated_ids'])) if a!=b),None)
        finite=all(torch.isfinite(torch.tensor([v for _,v in ts])).all().item() for ts in top)
        top5_ids_match=all([t for t,v in actual]==[t for t,v in expected] for actual,expected in zip(top,GOLD['top5']))
        observed_position=int(card.position.item())
        if observed_position!=card.pos:raise RuntimeError('device step count differs from consumed tokens')
        return {'ids':ids,'ids_match':matches,'first_divergence':first,'top5':top,'top5_differences':details,'top5_ids_match':top5_ids_match,'golden_token_logits_max_deviation':max(dev),'decode_ms':times,'decode_ms_median':statistics.median(times) if times else None,'timing_mode':'graph replay' if graph else 'per-launch Python enqueue','capture_ms':card.capture_ms,'device_position':observed_position,'argmax_ok':argmax_ok,'finite':finite}
    finally:
        if card.graph is not None:card.hip.release_graph(card.graph)

def child():
    state={'group':GROUP,'ok':False}
    try:
        import torch
        if GROUP!='readfirst':prepare()
        if GROUP=='readfirst':
            state.update(ok=True,result=readfirst_probe(torch))
        elif GROUP=='reference':
            if os.environ.get('AMDSERVE_REFERENCE','1')=='0':
                state.update(ok=True,status='NOT_RUN');say('REFERENCE (AMD library, not Omega) NOT_RUN; explicitly disabled by AMDSERVE_REFERENCE=0')
            else:
                result=reference(torch);state.update(ok=True,**result)
                say('REFERENCE (AMD library, not Omega) '+json.dumps(result))
        else:
            with torch.inference_mode():result=measure(torch,GROUP)
            if GROUP=='controls':
                caught=result['ids']!=GOLD['generated_ids'];state.update(ok=caught,result=result)
                say('CONTROLS omitted norm +1 '+('CAUGHT' if caught else 'ESCAPED')+' '+json.dumps(result))
            elif GROUP=='row-scales':
                state.update(ok=True,result=result)
                say('CONTROLS per-row scales diagnostic only (reported, not gating) '+json.dumps(result))
            else:
                ok=result['ids']==GOLD['generated_ids']
                state.update(ok=ok,result=result)
                say('OMEGA '+GROUP+' '+json.dumps(result));say('OMEGA top5/logit differences reported, not gating; CPU oracle comparison '+json.dumps(ORACLE))
                say('OMEGA timing: synchronized wall time, graph capture excluded; per-launch row includes Python submission/bounds/markers; replay row submits one executable graph; host readback and token selection excluded')
    except Exception as e:
        import traceback
        state['error']=traceback.format_exc();say(('REFERENCE NOT_RUN ' if GROUP=='reference' else 'ERROR ')+str(e))
        if GROUP=='reference':state.update(ok=True,status='NOT_RUN')
    finally:
        with STATE.open('a') as f:f.write(json.dumps(state)+'\n')
    return 0 if state['ok'] else 1
if __name__=='__main__':sys.exit(child() if GROUP else parent())
