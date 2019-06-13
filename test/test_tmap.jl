module TestTMap

using Test
using KissThreading

@testset "test tmap, tmap! correctness" begin
    dst = randn(3)
    src = randn(3)
    for (f, src) in [
              (sin  , (randn(3),)                      ),
              (+    , (randn(3), randn(3),)            ),
              (+    , (randn(6), randn(2,3),)          ),
              (x->x , (randn(100,100),)                ),
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

    @test_throws ArgumentError tmap(+, randn(5), randn(4))
    @test_throws ArgumentError tmap!(+, randn(4), randn(5), randn(4))
    @test_throws ArgumentError tmap!(+, randn(5), randn(5), randn(4))
end

end#module
