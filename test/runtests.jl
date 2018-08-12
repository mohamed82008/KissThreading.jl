using KissThreading
using Compat
using Compat.Test
using Compat.Random: GLOBAL_RNG
using Compat.Statistics: std, mean

include("bootstrap.jl")
include("bubblesort.jl")
include("sort_batch.jl")
include("summation.jl")
include("mapreduce.jl")

println("========")
