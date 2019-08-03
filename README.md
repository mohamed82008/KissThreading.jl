# KissThreading

[![Build Status](https://travis-ci.com/mohamed82008/KissThreading.jl.svg?branch=master)](https://travis-ci.com/mohamed82008/KissThreading.jl)
[![Build Status](https://ci.appveyor.com/api/projects/status/github/mohamed82008/KissThreading.jl?svg=true)](https://ci.appveyor.com/project/mohamed82008/KissThreading-jl)
[![Codecov](https://codecov.io/gh/mohamed82008/KissThreading.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/mohamed82008/KissThreading.jl)
[![Coveralls](https://coveralls.io/repos/github/mohamed82008/KissThreading.jl/badge.svg?branch=master)](https://coveralls.io/github/mohamed82008/KissThreading.jl?branch=master)

# Usage

KissThreading defines threaded versions of the following functions: `map, map!, mapreduce, reduce, sum, prod, minimum, maximum`
```julia
julia> using KissThreading

julia> using BenchmarkTools

julia> Threads.nthreads()
4

julia> data = randn(10^6);

julia> @btime sum(sin, data)
  13.114 ms (1 allocation: 16 bytes)
279.2390057547361

julia> @btime tsum(sin,data)
  3.722 ms (60 allocations: 4.09 KiB)
279.23900575473743

julia> @btime mapreduce(sin,*,data)
  15.607 ms (1 allocation: 16 bytes)
0.0

julia> @btime tmapreduce(sin,*,data)
  3.718 ms (60 allocations: 4.08 KiB)
0.0
```
