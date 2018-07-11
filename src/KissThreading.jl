module KissThreading

using Random: MersenneTwister
using Future: randjump

# export trandjump, TRNG, tmap!, tmapreduce, tmapadd, getrange

function trandjump(rng = MersenneTwister(0); jump=big(10)^20)
    n = Threads.nthreads()
    rngjmp = accumulate(randjump, [jump for i in 1:n], init = rng)
    Threads.@threads for i in 1:n
        rngjmp[i] = deepcopy(rngjmp[i])
    end
    rngjmp
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
function tmapreduce(f::Function, op::Function, v0::T, src::AbstractVector) where T 
    r = deepcopy(v0)
    i = Threads.Atomic{Int}(1)
    l = Threads.SpinLock()
    ls = length(src)
    nt = Threads.nthreads()
    return let r::T = r;
        Threads.@threads for j in 1:nt
            k = Threads.atomic_add!(i, 1)
            x = f(src[k])
            while true
                k = Threads.atomic_add!(i, 1)
                if k ≤ ls
                    x = op(x, f(src[k]))
                else
                    break
                end
            end
            Threads.lock(l)
            r = op(r, x)
            Threads.unlock(l)
        end
        r
    end
end

function tmapreduce(f::Function, op::Function, v0, src::AbstractVector...)
    lss = extrema(length.(src))
    lss[1] == lss[2] || throw(ArgumentError("src vectors must have the same lenth"))
    ls = lss[1]
    l = Threads.SpinLock()
    i = Threads.Atomic{Int}(1)

    r = deepcopy(v0)
    Threads.@threads for j in 1:Threads.nthreads()
        k = Threads.atomic_add!(i, 1)
        x = f(getindex.(src, k)...)
        while true
            k = Threads.atomic_add!(i, 1)
            if k ≤ ls
                x = op(x, f(getindex.(src,k)...))
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

function tmapadd(f::Function, v0, src::AbstractVector)
    ls = length(src)
    i = Threads.Atomic{Int}(1)
    r = Threads.Atomic{typeof(v0)}(zero(v0))
    Threads.@threads for j in 1:Threads.nthreads()
        x = zero(v0)
        while true
            k = Threads.atomic_add!(i, 1)
            if k ≤ ls
                @inbounds x += f(src[k])
            else
                break
            end
        end
        Threads.atomic_add!(r, x)
    end
    return v0 + r[]
end

function tmapadd(f::Function, v0, src::AbstractVector...)
    ls = length(src[1])
    i = Threads.Atomic{Int}(1)
    r = Threads.Atomic{typeof(v0)}(zero(v0))
    Threads.@threads for j in 1:Threads.nthreads()
        x = zero(v0)
        while true
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
