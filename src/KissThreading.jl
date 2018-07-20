module KissThreading

using Random: MersenneTwister
using Future: randjump

export trandjump, TRNG, tmap!, tmapreduce, tmapadd, getrange

function trandjump(rng = MersenneTwister(0); jump=big(10)^20)
    n = Threads.nthreads()
    rngjmp = accumulate(randjump, [jump for i in 1:n], init = rng)
    Threads.@threads for i in 1:n
        rngjmp[i] = deepcopy(rngjmp[i])
    end
    rngjmp
end

const TRNG = trandjump()

default_batch_size(n) = min(n, round(Int, 10*sqrt(n)))

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

mutable struct _RefType{T}
    value::T
end

# we assume that f.(src) and init are a subset of Abelian group with op
function tmapreduce(f::Function, op::Function, src::AbstractVector; init,
                    batch_size=default_batch_size(length(src)))
    r = _RefType(init) # code will fail if op returns different type than typeof(init)
    i = Threads.Atomic{Int}(1)
    l = Threads.SpinLock()
    ls = length(src)
    Threads.@threads for j in 1:Threads.nthreads()
        k = Threads.atomic_add!(i, batch_size)
        k > ls && continue
        x = f(src[k])
        for idx in (k+1):min(k+batch_size-1, ls)
            x = op(x, f(src[idx]))
        end
        k = Threads.atomic_add!(i, batch_size)
        while k ≤ ls
            for idx in k:min(k+batch_size-1, ls)
                x = op(x, f(src[idx]))
            end
            k = Threads.atomic_add!(i, batch_size)
        end
        Threads.lock(l)
        r.value = op(r.value, x)
        Threads.unlock(l)
    end
    r.value
end

function tmapreduce(f::Function, op::Function, src::AbstractVector...; init,
                    batch_size=default_batch_size(length(src[1])))
    lss = extrema(length.(src))
    lss[1] == lss[2] || throw(ArgumentError("src vectors must have the same length"))

    r = _RefType(init)
    i = Threads.Atomic{Int}(1)
    l = Threads.SpinLock()
    ls = lss[1]

        Threads.@threads for j in 1:Threads.nthreads()
        k = Threads.atomic_add!(i, batch_size)
        k > ls && continue
        x = f(getindex.(src, k)...)
        for idx in (k+1):min(k+batch_size-1, ls)
            x = op(x, f(getindex.(src, idx)...))
        end
        k = Threads.atomic_add!(i, batch_size)
        while k ≤ ls
            for idx in k:min(k+batch_size-1, ls)
                x = op(x, f(getindex.(src, idx)...))
            end
            k = Threads.atomic_add!(i, batch_size)
        end
        Threads.lock(l)
        r.value = op(r.value, x)
        Threads.unlock(l)
    end
    r.value
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
