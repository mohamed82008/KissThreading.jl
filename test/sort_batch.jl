src = [rand(10^4) for i in 1:10^4]

@testset "sort_batch" begin
    println("--------")
    println("tmap!")
    dst = similar(src)
    @time tmap!(sort, dst, src)
    @test all(issorted.(dst))

    println("simple")
    function simple(src, dst)
        @Threads.threads for k in 1:length(src)
            dst[k] = sort(src[k])
        end
    end

    dst = similar(src)
    @time simple(src, dst)
    @test all(issorted.(dst))
end
