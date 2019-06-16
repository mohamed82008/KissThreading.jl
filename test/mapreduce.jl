@testset "mapreduce" begin
    println("--------")
    n = 100000000
    a = rand(n)
    println("threaded tmapreduce: $(Threads.nthreads()) threads")
    @static if VERSION < v"0.7-"
        tmapreduce(log, +, 0.0, a)
        @time tmapreduce(log, +, 0.0, a)
    else
        tmapreduce(log, +, a, init=0.0)
        @time tmapreduce(log, +, a, init=0.0) 
    end

    println("unthreaded")
    mapreduce(log, +, a, init=0.0)
    @time mapreduce(log, +, a, init=0.0)

    @test tmapreduce(log, +, ones(1000), init=0.0) == 0
    Random.seed!(1234321)
    a = rand(1000)
    r1 = tmapreduce((x)->(2*x), +, a, init=0.0)
    r2 = mapreduce((x)->(2*x), +, a, init=0.0)
    @test r1 ≈ r2        
end
