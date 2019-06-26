using Random: MersenneTwister
using Future: randjump
export trandjump, TRNG

"""
    trandjump(rng = MersenneTwister(0); jump=big(10)^20)

Return a vector of copies of `rng`, which are advanced by different multiples
of `jump`. Effectively this produces statistically independent copies of `rng`
suitable for multi threading. See also [`Random.randjump`](@ref).
"""
function trandjump(rng = MersenneTwister(0); jump=big(10)^20)
    n = Threads.nthreads()
    rngjmp = Vector{MersenneTwister}(undef, n)
    for i in 1:n
        rngjmp[i] = randjump(rng, jump*i)
    end
    rngjmp
end

"""
    TRNG

A vector of statistically independent random number generators. Useful of threaded code:
```julia
rng = TRNG[Threads.threadid()]
rand(rng)
```
"""
TRNG
const TRNG = trandjump()
