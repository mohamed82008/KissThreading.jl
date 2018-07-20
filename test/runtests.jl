using Test
using KissThreading
using Random: GLOBAL_RNG
using Statistics: std, mean

include("bootstrap.jl")
include("bubblesort.jl")
include("sort_batch.jl")
include("summation.jl")

println("========")
