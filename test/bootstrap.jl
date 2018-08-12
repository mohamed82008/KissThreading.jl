src = [rand(400) for i in 1:100]

@testset "bootstrap test" begin
    println("--------")
    println("tmap!")
    dst = similar(src, Float64)
    @time begin
        tmap!(dst, src) do x
            rng = TRNG[Threads.threadid()]
            std([mean(rand(rng, x, length(x))) for i in 1:20000])
        end
    end
    @static if VERSION < v"0.7-"
        @test all(round.(std.(src)./dst/20, 1) .== 1.0)
    else
        @test all(round.(std.(src)./dst/20; digits=1) .== 1.0)
    end

    println("simple")
    function simple(src, dst)
        rngs = KissThreading._randjump(GLOBAL_RNG, Threads.nthreads())
        @Threads.threads for k in 1:length(src)
            x = src[k]
            rng = rngs[Threads.threadid()]
            dst[k] = std([mean(rand(rng, x, length(x))) for i in 1:20000])
        end
    end

    dst = similar(src, Float64)
    @time simple(src, dst)
    @static if VERSION < v"0.7-"
        @test all(round.(std.(src)./dst/20, 1) .== 1.0)
    else
        @test all(round.(std.(src)./dst/20; digits=1) .== 1.0)
    end
end
