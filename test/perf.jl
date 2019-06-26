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
        @btime $(base_call)
        print("Kiss: ")
        @btime $(tt_call)
        println("#"^80)
    end |> esc
end

@info "Running benchmarks on $(Threads.nthreads()) threads."
data = randn(10^6)
@race(sum,     sin, data)
@race(prod,    sin, data)
@race(minimum, sin, data)
@race(maximum, sin, data)
@race(mapreduce, sin, +, data)
@race(map, sin, data)

end#module
