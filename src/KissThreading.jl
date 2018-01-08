module KissThreading

export trandjump, TRNG, tmap!

function trandjump(rng = Base.GLOBAL_RNG)
    n = Threads.nthreads()
    rngjmp = randjump(rng, n+1)
    rngs = Vector{MersenneTwister}(n)
    Threads.@threads for i in 1:n
        tid = Threads.threadid()
        rngs[tid] = deepcopy(rngjmp[tid+1])
    end
    all([isassigned(rngs, i) for i in 1:n]) || error("failed to create rngs")
    rngs
end

const TRNG = trandjump()

function tmap!(f::Function, dst::AbstractVector, src::AbstractVector)
    if length(src) != length(dst)
        throw(ArgumentError("src and dst vectors must have the same length"))
    end
    
    i = Threads.Atomic{Int}(1)
    Threads.@threads for j in 1:Threads.nthreads()
        while true
            k = Threads.atomic_add!(i, 1)
            if k ≤ length(src)
                dst[k] = f(src[k])
            else
                break
            end
        end
    end
end

end

