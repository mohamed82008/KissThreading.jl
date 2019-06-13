module TestTMapreduce
using Test
using KissThreading

struct FreeAbelianSemigroup{T}
    coords::Dict{T, Int}
end

const FASG{T} = FreeAbelianSemigroup{T}

function Base.:*(x::FASG, y::FASG)
    FASG(merge(+, x.coords, y.coords))
end
Base.:(==)(x::FASG, y::FASG) = x.coords == y.coords
pure(x) = FASG(Dict(x=>1))

@testset "tmapreduce" begin
    for setup in [
        (f=identity, op=+, src=1:10,            init=0),
        (f=identity, op=+, src=1:10,            init=21),
        (f=identity, op=+, src=Int[],           init=0),
        (f=identity, op=+, src=Int[],           init=21),
        (f=x->2x,    op=*, src=collect(1:10),   init=21),
        (f=x->2x,    op=*, src=rand(Int, 10^5), init=rand(Int)),
        (f=pure,     op=*, src=randn(4),        init=pure(42.)),
        (f=pure,     op=*, src=randn(10^4),     init=pure(42.)),
       ]
        res_base = @inferred mapreduce(setup.f, setup.op, setup.src, init=setup.init)
        res_kiss = @inferred tmapreduce(setup.f, setup.op, setup.src, init=setup.init)
        @test res_base == res_kiss
    end
    @test tmapreduce(pure, *, 1:1, init=pure(-1)) == pure(-1) * pure(1)
    @test tmapreduce(pure, *, 1:1, init=pure(-1)) == mapreduce(pure, *, 1:1, init=pure(-1))

    # multiple src arrays
    @test 1:6 == @inferred tmapreduce(vcat, vcat, [1,3,5], [2,4,6], init=[])
    for setup in [
            (f=+, op=*, src=(1:10, 2:2:20), init=rand(Int)),
            (f=*, op=+, src=[rand(Int, 100) for _ in 1:5], init=rand(-10:10)),
            (f=pure∘tuple, op=*, src=[rand(-1:2, 100) for _ in 1:5], init=pure((1,2,3,4,5)))
       ]
        res_base = @inferred reduce(setup.op, map(setup.f, setup.src...), init=setup.init)
        res_kiss = @inferred tmapreduce(setup.f, setup.op, setup.src..., init=setup.init)
        @test res_base == res_kiss
    end

    # incompatible input size
    tmapreduce(+,*,randn(10), randn(10), init=0.)
    @test_throws ArgumentError tmapreduce(+,*,randn(10), randn(11), init=0.)
end

end#module
