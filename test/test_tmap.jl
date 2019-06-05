@testset "test tmap, tmap! correctness" begin
    dst = randn(3)
    src = randn(3)
    for (f, src) in [
              (sin,
               (randn(3),)
              ),
              (+,
               (randn(3), randn(3),)
              ),
              (x->x, 
               (randn(2,2),)
              ),
              (tuple,
               tuple([randn(1) for _ in 1:6]...),
              ),
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
    # map empty
    res = @inferred map(+, Int[], Float64[])
    @test res == Float64[]
end
