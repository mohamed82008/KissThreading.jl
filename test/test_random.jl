module TestRandom
using KissThreading
using Test
import Random

if Threads.nthreads() == 1
    @warn "There is only one thread. This limits, what can be tested."
end
@testset "trandjump" begin
    for _ in 1:10
        rng = Random.MersenneTwister(12352)
        jump = rand(Random.GLOBAL_RNG, 1:10)
        rngs = trandjump(rng, jump=jump);
        k = 2jump - 1
        rand(rng, k+1)
        for i in 1:length(rngs)
            @test rand(rng) == rand(rngs[i])
            rand(rng, k)
        end
    end
end

end#module
