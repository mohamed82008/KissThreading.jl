include("KissThreading.jl")

using KissThreading

src = [rand(10_000) for i in 1:100]
dst = similar(src)

println("running with $(Threads.nthreads()) thread(s)")
tic()
tmap!(src, dst) do x
    y = copy(x)
    n = length(x)
    for i in 1:n, j in 2:n
        if y[j-1] > y[j]
            y[j-1], y[j] = y[j], y[j-1]
        end
    end
    y
end
toc()
@assert all(issorted.(dst))

function simple(src, dst)
    @Threads.threads for k in 1:length(src)
        x = src[k]
        y = copy(x)
        n = length(x)
        for i in 1:n, j in 2:n
            if y[j-1] > y[j]
                y[j-1], y[j] = y[j], y[j-1]
            end
        end
        dst[k] = y
    end
end

tic()
simple(src, dst)
toc()
@assert all(issorted.(dst))

