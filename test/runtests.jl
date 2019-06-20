using KissThreading
using Test
using Statistics
using Random
using Random: GLOBAL_RNG

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

# @testset "getrange" begin
#     for _ in 1:10
#         n = rand(1:1000)
#         ranges = Threads.@threads for _ in 1:Threads.nthreads()
#             @inferred getrange(n)
#         end
#         @test sort!(vcat(ranges...)) == 1:n
#     end
# end

include("test_tmap.jl")
include("test_tmapreduce.jl")
include("bootstrap.jl")
include("bubblesort.jl")
include("sort_batch.jl")
include("summation.jl")
include("mapreduce.jl")

println("========")
