module Perf
using KissThreading
using KissThreading: tname
using BenchmarkTools

macro race(f, args...)
    tf = tname(f)
    tt_call   = :(($tf)($(args...)))
    base_call = :((Base.$f)($(args...)))
    call_str = string(:($f($(args...))))
    quote
        println("Benchmark: ", $call_str)
        print("Base: ")
        @btime $(base_call) evals=10 samples=10
        print("Kiss: ")
        @btime $(tt_call) evals=10 samples=10
        println("#"^80)
    end |> esc
end

@info "Running benchmarks on $(Threads.nthreads()) threads."
data = randn(10^5)
@race(sum,     sin, data)
@race(prod,    sin, data)
@race(minimum, sin, data)
@race(maximum, sin, data)
@race(reduce, atan, data)
@race(mapreduce, sin, +, data)
@race(map, sin, data)
dst = similar(data)
@race(map!, sin, dst, data)

end#module
