module TestTMapreduce
using Test
using KissThreading

struct FreeMonoid{T}
    word::Vector{T}
end

Base.:*(x::FreeMonoid, y::FreeMonoid) = FreeMonoid([x.word; y.word])
Base.:(==)(x::FreeMonoid, y::FreeMonoid) = x.word == y.word
pure(x) = FreeMonoid([x])
Base.one(::Type{FreeMonoid{T}}) where {T} = FreeMonoid{T}(T[])

@testset "tmapreduce" begin
    for setup in [
        (f=identity, op=+, src=1:10, init=0),
        (f=identity, op=+, src=1:10, init=21),
        (f=identity, op=+, src=Int[], init=0),
        (f=identity, op=+, src=Int[], init=21),
        (f=x->2x, op=*, src=collect(1:10), init=21),
        (f=x->2x, op=*, src=rand(Int, 10^5), init=rand(Int)),
       ]
        res_base = @inferred mapreduce(setup.f, setup.op, setup.src, init=setup.init)
        res_kiss = @inferred tmapreduce(setup.f, setup.op, setup.src, init=setup.init)
        @test res_base == res_kiss
    end
    @assert       mapreduce(pure, *, 1:1, init=pure(-1)) == FreeMonoid{Int64}([-1, 1])
    @test_broken tmapreduce(pure, *, 1:1, init=pure(-1)) == FreeMonoid{Int64}([-1, 1])


    # multiple src arrays
    @test 1:6 == @inferred tmapreduce(vcat, vcat, [1,3,5], [2,4,6], init=[])
    for setup in [
            (f=+, op=*, src=(1:10, 2:2:20), init=rand(Int)),
            (f=*, op=+, src=[rand(-10:10, 100) for _ in 1:5], init=rand(-10:10)),
       ]
        res_base = @inferred reduce(setup.op, map(setup.f, setup.src...), init=setup.init)
        res_kiss = @inferred tmapreduce(setup.f, setup.op, setup.src..., init=setup.init)
        @test res_base == res_kiss
    end


end

end#module
