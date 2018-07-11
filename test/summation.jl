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
@testset "summation: getrange" begin
    println("--------")
    println("threaded")
    f(z)
    @time _f = f(z)
    println("unthreaded")
    g(z)
    @time _g = g(z)
    @test _f ≈ _g
end
