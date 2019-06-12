import Random
using Random: AbstractRNG, MersenneTwister

struct ThreadedRNG{R<:AbstractRNG} <: AbstractRNG
    rngs::Vector{R}
    function ThreadedRNG(rngs)
        len = length(rngs)
        nt = Threads.nthreads()
        if len >= nt
            msg = """length(rngs) >= Threads.nthreads() must hold. Got:
            length(rngs) = $len
            Threads.nthreads() = $nt
            """
        end
        new(rngs)
    end
end

const GLOBAL_TRNG = ThreadedRNG(map(MersenneTwister, 1:Threads.nthreads()))

for f in [:rand, :randn, :rand!, :randn!]
    @eval @inline function Random.$f(o::ThreadedRNG, args...)
        index = Threads.threadid()
        @inbounds rng = o.rngs[index]
        $f(rng, args...)
    end
end
