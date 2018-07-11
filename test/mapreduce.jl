@testset "mapreduce" begin
    println("--------")
    println("threaded: $(Threads.nthreads()) threads")
    n = 10000000
    a = rand(n)
    tmapadd(log, 0., a)
    @time tmapadd(log, 0., a)
    println("unthreaded")
    mapreduce(log, +, a, init=0.)
    @time mapreduce(log, +, a, init=0.)

    @test tmapreduce(log, +, 0., ones(1000)) == 0
    srand(1234321)
    a = rand(1000)
    r1 = tmapreduce((x)->(2*x), +, 0., a)
    r2 = mapreduce((x)->(2*x), +, a, init=0.)
    @test r1 ≈ r2

    r3 = tmapadd((x)->(2*x), 0., a)
    @test r1 ≈ r3
end
