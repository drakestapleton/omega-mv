# ng-front kernel copies: provenance

These ten `.om` files are verbatim copies of the ng-bench lane's frozen kernels, taken by
`git fetch`-free file copy from the ng-bench checkout at omega-mv `3743d642cf034299009936eb8d458ba96a0a8589`
(`seed/ng/bench/kernels/`). Their origins are listed in that directory's `PROVENANCE.md`. They are the
run cases of `seed/ng/front/cases-front-ir.txt`; `gate-front-ir` compiles each with the pinned omc and
compares that binary's exit status and stdout with ngrun on the ΩIR that `ng` emits in `@ng front-ir` mode.
A changed file is a new case name, never an edit here.

```
d8700247b8d47e8cab2771b48a979a84615ef04acf40b975d6304af88ac25bb3  arith.om
022cb4d005ef7ecbe75686ac92459592a4ab388bf62f18fa5726171b454b4fa9  branch.om
d7c4796143291f036e844c7976b5438821c168bfeffdf3984e371bad84b8bf6a  fib38.om
685fe9e2385578ef7ddd2ab8076e9b7d30513c707bfd50161a4205e63dfe2d08  fib40.om
18321ee3a4c91326ff4ad42d54f1c2988c403b2d81cb79938dbcdf5347ba7bce  isort.om
5451d14ac27c98005f190d381d94ca28e6614ad2a725189e4ec2112adf5bd2e0  leafcall.om
b03808d01b0b211a8f23f10485f6dbab767dfe13e98d8f5a047607cea0801a2e  linear.om
0c6df9678ab2e74aaeea5830924fddf6375333e67fbdaab4907826a04769a86f  matmul.om
3efdb30a8d072a08af9d91e13c9ea6b1509fc7fc4f676cc1960725d76429239a  sieve.om
bab33a8c66922a456fcb75f1d87d5a8eeef6242aea6f7b266d38c2ba939a723c  sort.om
```

The hashes equal the ng-bench `PROVENANCE.md` table (checked with sha256sum after the copy).
