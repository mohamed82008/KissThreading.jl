@testset "mapreduce" begin
    println("--------")
    n = 10000000
    a = rand(n)
    println("threaded tmapreduce: $(Threads.nthreads()) threads")
    tmapreduce(log, +, a, init=0.0)
    @time tmapreduce(log, +, a, init=0.0)

    println("unthreaded")
    mapreduce(log, +, a, init=0.)
    @time mapreduce(log, +, a, init=0.)

    @test tmapreduce(log, +, ones(1000), init=0.0) == 0
    srand(1234321)
    a = rand(1000)
    r1 = tmapreduce((x)->(2*x), +, a, init=0.0)
    r2 = mapreduce((x)->(2*x), +, a, init=0.)
    r1 ≈ r2
end
