src = [rand(10^4) for i in 1:10^4]
dst = similar(src)

println("sort_batch\ntmap!")
tic()
tmap!(sort, dst, src)
toc()
@assert all(issorted.(dst))

println("simple")
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

