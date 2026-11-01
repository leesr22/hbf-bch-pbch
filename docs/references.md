# Primary implementation references

- Heegard/PLBC construction background: [Coding for Memory with Stuck-at Defects](https://arxiv.org/abs/1304.4821)
- Finite-length redundancy allocation: [Redundancy Allocation in Finite-Length Nested Codes for Nonvolatile Memories](https://arxiv.org/abs/1803.00117)
- BCH hardware architecture comparison: [Efficient Hardware Architectures for BCH Encoders and Decoders](https://arxiv.org/abs/2606.17837)
- Low-complexity BCH LFSR/Berlekamp-Massey implementation: [Low Complexity BCH Decoder Architecture for Emerging Wireless Body Area Networks](https://arxiv.org/abs/1408.2908)
- Parallel Chien-search patent: [US9413391B2](https://patents.google.com/patent/US9413391B2/en)
- GF(2) systolic elimination: [Systolic Gaussian Elimination over GF(2)](https://www.acsel-lab.com/arithmetic/arith8/papers/ARITH8_Hochet_Quinton_Robert.pdf)

No external RTL is copied.  These sources guided the choice of odd-syndrome
storage, inversionless BM, parallel Chien evaluation, and incremental pivot
basis.  The implementation in `rtl/` is independent and generated constants
are reproducible from `model/ecc.py` and `scripts/gen_rtl.py`.
