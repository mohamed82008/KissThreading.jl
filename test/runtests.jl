using Test
using KissThreading
using Random: GLOBAL_RNG, srand
using Statistics: std, mean

include("bootstrap.jl")
include("bubblesort.jl")
include("sort_batch.jl")
include("summation.jl")
include("mapreduce.jl")

println("========")
