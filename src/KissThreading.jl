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

default_batch_size(n) = min(n, round(Int, 10*sqrt(n)))

# we assume that f(src) is a subset of Abelian group with op
# and that v0 is its identity

function tmapreduce(f::Function, op::Function, v0::T, src::AbstractVector; batch_size=default_batch_size(length(src))) where T 
    r = deepcopy(v0)
    i = Threads.Atomic{Int}(1)
    l = Threads.SpinLock()
    ls = length(src)
    nt = Threads.nthreads()
    return let r::T = r;
        Threads.@threads for j in 1:nt
            k = Threads.atomic_add!(i, batch_size)
            if k <= ls
                x = f(src[k])
                range = (k+1):min(k+batch_size-1, ls)
                for idx in range
                    x = op(x, f(src[idx]))
                end
            else
                continue
            end
            k = Threads.atomic_add!(i, batch_size)
            while k ≤ ls
                range = k:min(k+batch_size-1, ls)
                for idx in range
                    x = op(x, f(src[idx]))
                end
                k = Threads.atomic_add!(i, batch_size)
            end
            Threads.lock(l)
            r = op(r, x)
            Threads.unlock(l)
        end
        r
    end
end

function tmapreduce(f::Function, op::Function, v0::T, src::AbstractVector...; batch_size=default_batch_size(length(src[1]))) where T
    lss = extrema(length.(src))
    lss[1] == lss[2] || throw(ArgumentError("src vectors must have the same length"))

    r = deepcopy(v0)
    i = Threads.Atomic{Int}(1)
    l = Threads.SpinLock()
    ls = lss[1]
    nt = Threads.nthreads()
    return let r::T = r;
        Threads.@threads for j in 1:nt
            k = Threads.atomic_add!(i, batch_size)
            if k <= ls
                x = f(getindex.(src, k)...)
                range = (k+1):min(k+batch_size-1, ls)
                for idx in range
                    x = op(x, f(getindex.(src, idx)...))
                end
            else
                continue
            end
            k = Threads.atomic_add!(i, batch_size)
            while k ≤ ls
                range = k:min(k+batch_size-1, ls)
                for idx in range
                    x = op(x, f(getindex.(src, idx)...))
                end
                k = Threads.atomic_add!(i, batch_size)
            end
            Threads.lock(l)
            r = op(r, x)
            Threads.unlock(l)
        end
        r
    end
end

function tmapadd(f::Function, v0::T, src::AbstractVector; batch_size=default_batch_size(length(src))) where T
    r = Threads.Atomic{T}(deepcopy(v0))
    i = Threads.Atomic{Int}(1)
    ls = length(src)
    nt = Threads.nthreads()
    Threads.@threads for j in 1:nt
        k = Threads.atomic_add!(i, batch_size)
        if k <= ls
            x = f(src[k])
            range = (k+1):min(k+batch_size-1, ls)
            for idx in range
                x += f(src[idx])
            end
        else
            continue
        end
        k = Threads.atomic_add!(i, batch_size)
        while k ≤ ls
            range = k:min(k+batch_size-1, ls)
            for idx in range
                x += f(src[idx])
            end
            k = Threads.atomic_add!(i, batch_size)
        end
        Threads.atomic_add!(r, x)
    end
    return r[]
end

function tmapadd(f::Function, v0::T, src::AbstractVector...; batch_size=default_batch_size(length(src[1]))) where T
    lss = extrema(length.(src))
    lss[1] == lss[2] || throw(ArgumentError("src vectors must have the same length"))

    r = Threads.Atomic{T}(deepcopy(v0))
    i = Threads.Atomic{Int}(1)
    ls = lss[1]
    nt = Threads.nthreads()
    Threads.@threads for j in 1:nt
        k = Threads.atomic_add!(i, batch_size)
        if k <= ls
            x = f(getindex.(src, k)...)
            range = (k+1):min(k+batch_size-1, ls)
            for idx in range
                x += f(getindex.(src, idx)...)
            end
        else
            continue
        end
        k = Threads.atomic_add!(i, batch_size)
        while k ≤ ls
            range = k:min(k+batch_size-1, ls)
            for idx in range
                x += f(getindex.(src, idx)...)
            end
            k = Threads.atomic_add!(i, batch_size)
        end
        Threads.atomic_add!(r, x)
    end
    return r[]
end

function getrange(n)
    tid = Threads.threadid()
    nt = Threads.nthreads()
    d , r = divrem(n, nt)
    from = (tid - 1) * d + min(r, tid - 1) + 1
    to = from + d - 1 + (tid ≤ r ? 1 : 0)
    from:to
end

function getrange(n, k, bs)
    tid = Threads.threadid()
    nt = Threads.nthreads()
    d , r = divrem(n, nt)
    from = (tid - 1) * d + min(r, tid - 1) + 1
    to = from + d - 1 + (tid ≤ r ? 1 : 0)
    from:to
end

end
