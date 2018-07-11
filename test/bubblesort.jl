src = [rand(10_000) for i in 1:100]

@testset "bubblesort" begin
    println("--------")
    println("tmap!")
    dst = similar(src)
    @time begin
        tmap!(dst, src) do x
            y = copy(x)
            n = length(x)
            for i in 1:n, j in 2:n
                if y[j-1] > y[j]
                    y[j-1], y[j] = y[j], y[j-1]
                end
            end
            y
        end
    end
    @test all(issorted.(dst))

    println("simple")
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

    dst = similar(src)
    @time simple(src, dst)
    @test all(issorted.(dst))
end
