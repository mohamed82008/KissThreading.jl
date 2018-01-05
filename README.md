# KissThreading.jl
Simple patterns supporting working with threads in Julia

Comparison of performance `tmap!` threading with copied random number generators and standard `@Threading.threads`.
Tests run on 16 core AWS c4.4xlarge instance by running *src/runtests.sh*.
We measure time using `@time` so `tmap!` has more of precompilation overhead reported.

### `bootstrap.jl`
![bootstrap.png](bootstrap.png)

### `bubble.jl`
![bubble.png](bubble.png)

