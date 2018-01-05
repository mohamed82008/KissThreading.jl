include("KissThreading.jl")

using KissThreading

src = [rand(10) for i in 3*1:10^7]
dst = similar(src)

println("running with $(Threads.nthreads()) thread(s)")

tic()
tmap!(sort, dst, src)
toc()
@assert all(issorted.(dst))

function simple(src, dst)
    @Threads.threads for k in 1:length(src)
        dst[k] = sort(src[k])
    end
end

dst = similar(src)
tic()
simple(src, dst)
toc()
@assert all(issorted.(dst))

