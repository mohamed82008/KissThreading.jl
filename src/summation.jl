include("KissThreading.jl")

using KissThreading
using BenchmarkTools

println("running with $(Threads.nthreads()) thread(s)")


function f(x)
    s = Threads.Atomic{Float64}(0.0)
    n = length(x)
    @Threads.threads for k in 1:Threads.nthreads()
        y = 0.0
        @inbounds @simd for i in getrange(n)
            y += x[i]
        end
        Threads.atomic_add!(s, y)
    end
    s[]
end

function g(x)
    n = length(x)
    s = 0.0
    @inbounds @simd for i in 1:n
        s += x[i]
    end
    s
end

z = rand(10^8)
display(@benchmark f($z))
println()
display(@benchmark g($z))

