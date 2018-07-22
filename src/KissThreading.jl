module KissThreading

using Random: MersenneTwister
using Future: randjump

export trandjump, TRNG, tmap!, tmapreduce, tmapadd, getrange

_randjump(rng, n, jump=big(10)^20) = accumulate(randjump, [jump for i in 1:n], init = rng)

function trandjump(rng = MersenneTwister(0); jump=big(10)^20)
    n = Threads.nthreads()
    rngjmp = _randjump(rng, n, jump)
    Threads.@threads for i in 1:n
        rngjmp[i] = deepcopy(rngjmp[i])
    end
    rngjmp
end

const TRNG = trandjump()

default_batch_size(n) = min(n, round(Int, 10*sqrt(n)))

function tmap!(f::Function, dst::AbstractVector, src::AbstractVector...; batch_size=1)
    ld = length(dst)
    if (ld, ld) != extrema(length.(src))
        throw(ArgumentError("src and dst vectors must have the same length"))
    end
    
    i = Threads.Atomic{Int}(1)
    Threads.@threads for j in 1:Threads.nthreads()
        while true
            k = Threads.atomic_add!(i, 1)
            batch_start = 1 + (k-1) * batch_size
            batch_end = min(k * batch_size, ld)
            batch_start > ld && break
            for j in batch_start:batch_end
                dst[j] = f(getindex.(src, j)...)
            end
        end
    end
end

# we assume that f.(src) and init are a subset of Abelian group with op
function tmapreduce(f::Function, op::Function, src...; init,
    batch_size=default_batch_size(length(src[1])))

    T = get_reduction_type(init, f, op, src...)
    result = MapReduceResult(T(init), op)
    result(batch_size, init, f, op, src...)
end
@inline function get_reduction_type(init, f, op, src...)
    Tx = Core.Compiler.return_type(f, Tuple{eltype.(src)...})
    Trinit = Core.Compiler.return_type(op, Tuple{typeof(init), Tx})
    Tr = Core.Compiler.return_type(op, Tuple{Trinit, Tx})
    return Tr
end
mutable struct MapReduceResult{T, TO}
    value::T
    op::TO
end
@inline function (result::MapReduceResult)(batch_size, init, f, op, src...)
    lss = extrema(length.(src))
    lss[1] == lss[2] || throw(ArgumentError("src vectors must have the same length"))
    op = result.op
    i = Threads.Atomic{Int}(1)
    l = Threads.SpinLock()
    ls = lss[1]
    Threads.@threads for j in 1:Threads.nthreads()
        k = Threads.atomic_add!(i, batch_size)
        k > ls && continue
        mapreducer = MapReducer(init, k, f, op, src...)
        range = (k + 1) : min(k + batch_size - 1, ls)
        mapreducer = mapreducer(range)
        k = Threads.atomic_add!(i, batch_size)
        while k ≤ ls
            range = (k + 1) : min(k + batch_size - 1, ls)
            mapreducer = mapreducer(range)
            k = Threads.atomic_add!(i, batch_size)
        end
        Threads.lock(l)
        result.value = op(result.value, mapreducer.r)
        Threads.unlock(l)
    end
    result.value
end
struct MapReducer{TR, TF, TO, TS}
    r::TR
    f::TF
    op::TO
    src::TS
end
@inline function (::Type{<:MapReducer})(init, initidx, f, op, src...)
    T = get_reduction_type(init, f, op, src...)
    r = T(f(getindex.(src, initidx)...))
    N = length(src)
    MapReducer(r, f, op, src)    
end
@inline function (m::MapReducer)(range)
    r, f, op, src = m.r, m.f, m.op, m.src
    for i in range
        r = op(r, f(getindex.(src, i)...))
    end
    return typeof(m)(r, f, op, src)
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
