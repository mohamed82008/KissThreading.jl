module TestTMap

using Test
using KissThreading
using KissThreading: Batches

@testset "Batches" begin
    for _ in 1:10
        start = rand(-1000:1000)
        stop = start + rand(1:1000)
        inds = start:stop
        batch_size = rand(1:1000)
        b = Batches(inds, batch_size)
        @test vcat([b[i] for i in eachindex(b)]...) == inds
    end
    
    inds = Base.OneTo(rand(1:1000))
    batch_size = rand(1:1000)
    b = Batches(inds, batch_size)
    @test vcat([b[i] for i in eachindex(b)]...) == inds
end


@testset "test tmap, tmap! correctness" begin

    src = (1:2, [1.0, 2.0], [false, true])
    @test map(*, src...) ==  tmap(*, src...)

    for (f, src) in [
              (tuple, tuple([randn(2) for _ in 1:3]...)),
              (sin  , (randn(3),)                      ),
              (+    , (randn(3), randn(3),)            ),
              (+    , (randn(6), randn(2,3),)          ),
              (x->x , (randn(100,100),)                ),
              (atan , (randn(10^4), randn(10^4))       ),
              (*    , (1:2, randn(2), [true, false])   ),
              (tuple, tuple([randn(1) for _ in 1:3]...)),
             ]
        src1 = first(src)
        y = f(getindex.(src, 1)...)
        T = typeof(y)
        dst_map = similar(src1, T)
        dst_tmap = similar(src1, T)

        res_map!  = @inferred map!(f, dst_map, src...)
        res_tmap! = @inferred tmap!(f, dst_tmap, src...)
        res_map   = @inferred map(f, src...)
        res_tmap  = @inferred tmap(f, src...)
        @test typeof(res_map) == typeof(res_tmap)
        @test res_map == res_tmap
        @test res_map! == res_tmap!
    end
    # tmap empty
    res = @inferred tmap(+, Int[], Float64[])
    @test res == Float64[]

    @test_throws DimensionMismatch tmap(+, randn(5), randn(4))
    @test_throws DimensionMismatch tmap!(+, randn(4), randn(5), randn(4))
    @test_throws DimensionMismatch tmap!(+, randn(5), randn(5), randn(4))
end

end#module
