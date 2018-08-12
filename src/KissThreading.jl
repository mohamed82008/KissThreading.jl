module KissThreading

using Compat.Random: MersenneTwister
@static if VERSION >= v"0.7-"
    using Future: randjump
end

export trandjump, TRNG, tmap!, tmapreduce, getrange

@static if VERSION < v"0.7-"
    const _randjump = randjump
    
    function trandjump(rng = MersenneTwister(0), gpt=1)
        n = Threads.nthreads()
        # create gpt+1 RNGs, but leave gpt
        # generator number gpt+1 is dropped to have rngs for each thread separated in memory
        rngjmp = randjump(rng, n*(gpt+1))
        reshape(rngjmp, (gpt+1, n))[1:gpt, :]
    end
else
    _randjump(rng, n, jump=big(10)^20) = accumulate(randjump, [jump for i in 1:n], init = rng)
    
    function trandjump(rng = MersenneTwister(0); jump=big(10)^20)
        n = Threads.nthreads()
        rngjmp = accumulate(randjump, [jump for i in 1:n], init = rng)
        Threads.@threads for i in 1:n
            rngjmp[i] = deepcopy(rngjmp[i])
        end
        rngjmp
    end    
end

const TRNG = trandjump()

default_batch_size(n) = min(n, round(Int, 10*sqrt(n)))

struct Mapper
    atomic::Threads.Atomic{Int}
    len::Int
end

@inline function (mapper::Mapper)(batch_size, f, dst, src...)
    ld = mapper.len
    atomic = mapper.atomic
    Threads.@threads for j in 1:Threads.nthreads()
        while true
            k = Threads.atomic_add!(atomic, 1)
            batch_start = 1 + (k-1) * batch_size
            batch_end = min(k * batch_size, ld)
            batch_start > ld && break
            batch_map!(batch_start:batch_end, f, dst, src...)
        end
    end
    dst
end

@inline function batch_map!(range, f, dst, src...)
    @inbounds for j in range
        dst[j] = f(getindex.(src, j)...)
    end
end

function tmap!(f, dst::AbstractArray, src::AbstractArray...; batch_size=1)
    ld = length(dst)
    if (ld, ld) != extrema(length.(src))
        throw(ArgumentError("src and dst vectors must have the same length"))
    end
    atomic = Threads.Atomic{Int}(1)
    mapper = Mapper(atomic, ld)
    mapper(batch_size, f, dst, src...)
end

struct MapReducer{T}
    r::Base.RefValue{T}
    atomic::Threads.Atomic{Int}
    lock::Threads.SpinLock
    len::Int
end

@inline function (mapreducer::MapReducer{T})(batch_size, f, op, src...) where T
    atomic = mapreducer.atomic
    lock = mapreducer.lock
    len = mapreducer.len
    Threads.@threads for j in 1:Threads.nthreads()
        k = Threads.atomic_add!(atomic, batch_size)
        k > len && continue
        r = T(f(getindex.(src, k)...))
        range = (k + 1) : min(k + batch_size - 1, len)
        r = batch_mapreduce(r, range, f, op, src...)
        k = Threads.atomic_add!(atomic, batch_size)
        while k ≤ len
            range = k : min(k + batch_size - 1, len)
            r = batch_mapreduce(r, range, f, op, src...)
            k = Threads.atomic_add!(atomic, batch_size)
        end
        Threads.lock(lock)
        mapreducer.r[] = op(mapreducer.r[], r)
        Threads.unlock(lock)
    end
    mapreducer.r[]
end

@static if VERSION < v"0.7-"
    # we assume that f.(src) and init are a subset of Abelian group with op
    function tmapreduce(f, op, init, src::AbstractArray...; batch_size=default_batch_size(length(src[1])))
        T = get_reduction_type(init, f, op, src...)
        _tmapreduce(T, init, batch_size, f, op, src...)
    end

    function tmapreduce(::Type{T}, f, op, init, src::AbstractArray...; batch_size=default_batch_size(length(src[1]))) where T
        _tmapreduce(T, init, batch_size, f, op, src...)
    end
else
    # we assume that f.(src) and init are a subset of Abelian group with op
    function tmapreduce(f, op, src::AbstractArray...; init, batch_size=default_batch_size(length(src[1])))
        T = get_reduction_type(init, f, op, src...)
        _tmapreduce(T, init, batch_size, f, op, src...)
    end

    function tmapreduce(::Type{T}, f, op, src::AbstractArray...; init, batch_size=default_batch_size(length(src[1]))) where T
        _tmapreduce(T, init, batch_size, f, op, src...)
    end
end

@inline function _tmapreduce(::Type{T}, init, batch_size, f, op, src...) where T
    lss = extrema(length.(src))
    lss[1] == lss[2] || throw(ArgumentError("src vectors must have the same length"))

    atomic = Threads.Atomic{Int}(1)
    lock = Threads.SpinLock()
    len = lss[1]
    mapreducer = MapReducer{T}(Base.RefValue{T}(init), atomic, lock, len)
    return mapreducer(batch_size, f, op, src...)
end

@static if VERSION < v"0.7-"
    const return_type = Core.Inference.return_type
else
    const return_type = Core.Compiler.return_type
end

@inline function get_reduction_type(init, f, op, src...)
    Tx = return_type(f, Tuple{eltype.(src)...})
    Trinit = return_type(op, Tuple{typeof(init), Tx})
    Tr = return_type(op, Tuple{Trinit, Tx})
    Tr === Union{} ? typeof(init) : Tr
end

@inline function batch_mapreduce(r, range, f, op, src...)
    @inbounds for i in range
        r = op(r, f(getindex.(src, i)...))
    end
    r
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
