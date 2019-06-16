using KissThreading
using Test
using Statistics
using Random
using Random: GLOBAL_RNG

include("test_tmap.jl")
include("test_tmapreduce.jl")
include("bootstrap.jl")
include("bubblesort.jl")
include("sort_batch.jl")
include("summation.jl")
include("mapreduce.jl")

println("========")
