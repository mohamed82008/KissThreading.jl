module TestTMapreduce

using Test
using KissThreading
using BenchmarkTools: @benchmark

const MAX_ALLOCS = 120

struct FreeMonoid{T}
    word::Vector{T}
end

function Base.:*(x::FreeMonoid, y::FreeMonoid)
    FreeMonoid(vcat(x.word, y.word))
end
Base.:(==)(x::FreeMonoid, y::FreeMonoid) = x.word == y.word
pure(x) = FreeMonoid([x])
Base.one(::Type{FreeMonoid{T}}) where {T} = FreeMonoid{T}(T[])

@testset "sum, prod, minimum, maximum" begin
    
    for (f, arr) in [
            (identity, [1]),
            (sin, randn(10)),
            (identity, randn(10)),
            (x -> 2x, rand(Int, 10000)),
        ]
        @test Base.prod(arr) ≈ @inferred tprod(arr)
        @test Base.sum(arr) ≈ @inferred tsum(arr)
        @test Base.minimum(arr) === @inferred tminimum(arr)
        @test Base.maximum(arr) === @inferred tmaximum(arr)

        @test Base.prod(f, arr) ≈ @inferred tprod(f, arr)
        @test Base.sum(f, arr) ≈ @inferred tsum(f, arr)
        @test Base.minimum(f, arr) === @inferred tminimum(f, arr)
        @test Base.maximum(f, arr) === @inferred tmaximum(f, arr)
    end

    # empty
    @test_throws ArgumentError tmaximum(Int[])
    @test_throws ArgumentError tminimum(Int[])
    @test tprod(Int[]) === 1
    @test tsum(Int[]) === 0

    @test tsum([1,2,3], batch_size=100) === 6
    @test tsum(x->2x, [1,2,3], batch_size=100) === 12
    @test_throws ArgumentError tsum([1,2,3], batch_size=-100)

    # performance
    data = randn(10^5)
    for red in [tsum, tprod, tminimum, tmaximum]
        b = @benchmark ($red)($data) samples=1 evals=1
        @test b.allocs < MAX_ALLOCS
        b = @benchmark ($red)(sin, $data) samples=1 evals=1
        @test b.allocs < MAX_ALLOCS
    end
end

@testset "treduce, tmapreduce" begin
    @test tmapreduce(pure, *, 1:1, init=pure(-1)) == pure(-1) * pure(1)
    @test tmapreduce(pure, *, 1:1, init=pure(-1)) == mapreduce(pure, *, 1:1, init=pure(-1))

    @test tmapreduce(identity, +, Int[], init=4) == 4
    @test tmapreduce(identity, +, Int[]) == 0
    @test treduce(+, Int[]) == 0

    @test treduce(+, [1,2,3], batch_size=3) === 6
    @test tmapreduce(x->2x, +, [1,2,3], batch_size=3) === 12

    setups = [
                  (f=identity,       op=+, srcs=(1:10,),                    init=0),
                  (f=identity,       op=*, srcs=(String[],),                init="Hello"),
                  (f=identity,       op=+, srcs=(1:10,),                    init=21),
                  (f=x->2x,          op=*, srcs=(collect(1:10),),           init=21),
                  (f=x->2x,          op=*, srcs=(rand(Int, 10^5),),         init=rand(Int)),
                  (f=pure,           op=*, srcs=(randn(4),),                init=pure(42.0)),
                  (f=pure,           op=*, srcs=(randn(10^4),),             init=pure(42.0)),
       ]

    # multi arg mapreduce
    if VERSION >= v"1.2-"
        for n in 1:4
            s= (f=pure∘tuple,  op=*, srcs=[Float64[1] for _ in 1:n], init=pure(tuple(1.0:n...)))
            push!(setups, s)
        end
    else
        @warn "Skipping multi arg mapreduce tests, on julia $VERSION"
    end

    for setup in setups

        res_base = @inferred Base.reduce(setup.op, map(setup.f, setup.srcs...))
        res_tt   = @inferred   treduce(setup.op, map(setup.f, setup.srcs...))
        @test res_base == res_tt

        res_base = @inferred Base.reduce(setup.op, map(setup.f, setup.srcs...), init=setup.init)
        res_tt   = @inferred   treduce(setup.op, map(setup.f, setup.srcs...), init=setup.init)
        @test res_base == res_tt

        res_base = @inferred Base.mapreduce(setup.f, setup.op, setup.srcs...)
        res_tt   = @inferred   tmapreduce(setup.f, setup.op, setup.srcs...)
        @test res_base == res_tt

        res_base = @inferred Base.mapreduce(setup.f, setup.op, setup.srcs..., init=setup.init)
        res_tt   = @inferred   tmapreduce(setup.f, setup.op, setup.srcs..., init=setup.init)
        @test res_base == res_tt
    end

    # performance
    data = randn(10^5)
    b = @benchmark tmapreduce(sin, +, $data) samples=1 evals=1
    @test b.allocs < MAX_ALLOCS

    b = @benchmark treduce(+, $data) samples=1 evals=1
    @test b.allocs < MAX_ALLOCS
end

end#module
