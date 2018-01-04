# KissThreading.jl
Simple patterns supporting working with threads in Julia

Comparison of performance `tmap!` threading with copied random number generators and standard `@Threading.threads`.
Tests run on 16 core AWS c4.4xlarge instance by running *src/runtests.sh*.

### `bootstrap.jl`
![bootstrap.png](bootstrap.png)

### `bubble.jl`
![bubble.png](bubble.png)

