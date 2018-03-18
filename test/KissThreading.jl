module KissThreading

export trandjump, TRNG, tmap!, tmapreduce, tmapadd, getrange

# gpt is generators per thread
# return value each column are generators for a single thread
function trandjump(rng = MersenneTwister(0), gpt=1)
    n = Threads.nthreads()
    # create gpt+1 RNGs, but leave gpt
    # generator number gpt+1 is dropped to have rngs for each thread separated in memory
    rngjmp = randjump(rng, n*(gpt+1))
    reshape(rngjmp, (gpt+1, n))[1:gpt, :]
end

const TRNG = trandjump()

function tmap!(f::Function, dst::AbstractVector, src::AbstractVector)
    ld = length(dst)
    if ld != length(src)
        throw(ArgumentError("src and dst vectors must have the same length"))
    end
    
    i = Threads.Atomic{Int}(1)
    Threads.@threads for j in 1:Threads.nthreads()
        while true
            k = Threads.atomic_add!(i, 1)
            if k ≤ ld
                dst[k] = f(src[k])
            else
                break
            end
        end
    end
end

function tmap!(f::Function, dst::AbstractVector, src::AbstractVector...)
    ld = length(dst)
    if (ld, ld) != extrema(length.(src))
        throw(ArgumentError("src and dst vectors must have the same length"))
    end
    
    i = Threads.Atomic{Int}(1)
    Threads.@threads for j in 1:Threads.nthreads()
        while true
            k = Threads.atomic_add!(i, 1)
            if k ≤ ld
                dst[k] = f(getindex.(src, k)...)
            else
                break
            end
        end
    end
end

# we assume that f(src) is a subset of Abelian group with op
# and that v0 is its identity
function tmapreduce!(f::Function, op::Function, v0, src::AbstractVector)
    ls = length(src)
    l = Threads.SpinLock()
    i = Threads.Atomic{Int}(1)
    r = deepcopy(v0)
    Threads.@threads for j in 1:Threads.nthreads()
        x = deepcopy(v0)
        while true
            k = Threads.atomic_add!(i, 1)
            if k ≤ ls
                dst[k] = f(src[k])
            else
                break
            end
        end
        Threads.lock(l)
        r = op(r, x)
        Threads.unlock(l)
    end
    return r
end

function tmapreduce!(f::Function, op::Function, v0, src::AbstractVector...)
    lss = extrema(length.(src))
    lss[1] == lss[2] || throw(ArgumentError("src vectors must have the same lenth"))
    ls = lss[1]
    l = Threads.SpinLock()
    i = Threads.Atomic{Int}(1)
    r = deepcopy(v0)
    Threads.@threads for j in 1:Threads.nthreads()
        x = deepcopy(v0)
        while true
            k = Threads.atomic_add!(i, 1)
            if k ≤ ls
                x += f(getindex.(src, k)...)
            else
                break
            end
        end
        Threads.lock(l)
        r = op(r, x)
        Threads.unlock(l)
    end
    return r
end

function tmapadd!(f::Function, v0, src::AbstractVector)
    ls = length(src)
    i = Threads.Atomic{Int}(1)
    r = Threads.Atomic{typeof(v0)}(zero(v0))
    Threads.@threads for j in 1:Threads.nthreads()
        while true
            x = zero(v0)
            k = Threads.atomic_add!(i, 1)
            if k ≤ ls
                x += f(src[k])
            else
                break
            end
        end
        Threads.atomic_add!(r, x)
    end
    return v0 + r[]
end

function tmapadd!(f::Function, v0, src::AbstractVector...)
    ls = length(src)
    i = Threads.Atomic{Int}(1)
    r = Threads.Atomic{typeof(v0)}(zero(v0))
    Threads.@threads for j in 1:Threads.nthreads()
        while true
            x = zero(v0)
            k = Threads.atomic_add!(i, 1)
            if k ≤ ls
                x += f(getindex.(src, k)...)
            else
                break
            end
        end
        Threads.atomic_add!(r, x)
    end
    return v0 + r[]
end

function getrange(n)
    tid = Threads.threadid()
    nt = Threads.nthreads()
    d , r = divrem(n, nt)
    from = (tid - 1) * d + min(r, tid - 1) + 1
    to = from + d - 1 + (tid ≤ r ? 1 : 0)
    from:to
end

end

