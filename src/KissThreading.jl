module KissThreading

using Random: MersenneTwister
using Future: randjump
using Core.Compiler: return_type

export trandjump, TRNG, tmap, tmap!, tmapreduce, getrange

"""
    trandjump(rng = MersenneTwister(0); jump=big(10)^20)

Return a vector of copies of `rng`, which are advanced by different multiples
of `jump`. Effectively this produces statistically independent copies of `rng`
suitable for multi threading. See also [`Random.randjump`](@ref).
"""
function trandjump end

_randjump(rng, n, jump=big(10)^20) = accumulate(randjump, [jump for i in 1:n], init = rng)

function trandjump(rng = MersenneTwister(0); jump=big(10)^20)
    n = Threads.nthreads()
    rngjmp = Vector{MersenneTwister}(undef, n)
    for i in 1:n
        rngjmp[i] = randjump(rng, jump*i)
    end
    rngjmp
end

const TRNG = trandjump()

"""
    TRNG

A vector of statistically independent random number generators. Useful of threaded code:
```julia
rng = TRNG[Threads.threadid()]
rand(rng)
```
"""
TRNG

############################## tmap!
function _doc_threaded_version(f)
    """Threaded version of [`$f`](@ref). The workload is divided into chunks of length `batch_size`
    and processed by the threads. For very cheap `f` it can be advantageous to increase `batch_size`."""
end

"""
    tmap!(f, dst::AbstractArray, src::AbstractArray...; batch_size=1)

$(_doc_threaded_version(map!))
"""
function tmap! end

struct Batches{V}
    firstindex::Int
    lastindex::Int
    batch_size::Int
    values::V
    length::Int
end

function Batches(values, batch_size::Integer)
    @assert batch_size > 0
    r = eachindex(values)
    @assert r isa AbstractUnitRange
    len = ceil(Int, length(r) / batch_size)
    Batches(first(r), last(r), batch_size, values, len)
end

Base.length(o::Batches) = o.length
Base.eachindex(o::Batches) = Base.OneTo(length(o))
function Base.getindex(o::Batches, i)
    start = o.firstindex + (i-1) * o.batch_size
    stop  = min(start + (o.batch_size) -1, o.lastindex)
    o.values[start:stop]
end

function default_batch_size(len)
    len <= 1 && return 1
    nthreads=Threads.nthreads()
    items_per_thread = len/nthreads
    items_per_batch = items_per_thread/4
    clamp(1, round(Int, len / items_per_batch), len)
end

function Base.iterate(o::Batches, state=1)
    if state in eachindex(o)
        o[state], state+1
    else
        nothing
    end
end

mutable struct _RollingCutOut{A,I<:AbstractUnitRange,T} <: AbstractVector{T}
    array::A
    eachindex::I
end

function _RollingCutOut(array::AbstractArray, indices)
    T = eltype(array)
    A = typeof(array)
    I = typeof(indices)
    _RollingCutOut{A, I, T}(array, indices)
end

Base.size(r::_RollingCutOut) = (length(r.eachindex),)

function Base.eachindex(r::_RollingCutOut, rs::_RollingCutOut...)
    for r2 in rs
        @assert r.eachindex == r2.eachindex
    end
    Base.IdentityUnitRange(r.eachindex)
end
Base.axes(r::_RollingCutOut) = (eachindex(r),)

@inline function Base.getindex(o::_RollingCutOut, i)
    @boundscheck checkbounds(o, i)
    @inbounds o.array[i]
end

@inline function Base.setindex!(o::_RollingCutOut, val, i)
    @boundscheck checkbounds(o, i)
    @inbounds o.array[i] = val
end

function tmap!(f, dst, srcs...; 
        batch_size=default_batch_size(length(dst)))

    isempty(first(srcs)) && return dst
    # we use IndexLinear since _RollingCutOut implementation
    # does not support other indexing well
    all_inds  = eachindex(IndexLinear(), srcs...)
    batches   = Batches(all_inds, batch_size)
    sample_inds = batches[1]
    nt = Threads.nthreads()
    arena_dst_view  = [_RollingCutOut(dst, sample_inds) for _ in 1:nt]
    arena_src_views = [[_RollingCutOut(src, sample_inds) for src in srcs] for _ in 1:nt]

    for i in eachindex(batches)
        tid = Threads.threadid()
        dst_view  = arena_dst_view[tid]
        src_views = arena_src_views[tid]
        inds = batches[i]
        dst_view.eachindex = inds
        for view in src_views
            view.eachindex = inds
        end
        map!(f, dst_view, src_views...)
    end
    dst
end

"""
    tmap(f, src::AbstractArray...; batch_size=1)

$(_doc_threaded_version(map))
"""
function tmap(f, src::AbstractArray...; batch_size=1)
    g = Base.Generator(f,src...)
    T = Base.@default_eltype(g)
    dst = similar(first(src), T)
    tmap!(f, dst, src..., batch_size=batch_size)
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
        y = f(getindex.(src, k)...)
        r = convert(T, y)
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

"""
    tmapreduce(f, op, src::AbstractArray...; init, batch_size=default_batch_size(length(src[1])))

$(_doc_threaded_version(mapreduce))

Warning: In contrast to `Base.mapreduce` it is assumed that `op` must be commutative. Otherwise
the result is undefined.
"""
function tmapreduce end

function tmapreduce(f, op, src::AbstractArray...; init, batch_size=default_batch_size(length(src[1])))
    T = get_reduction_type(init, f, op, src...)
    _tmapreduce(T, init, batch_size, f, op, src...)
end

function tmapreduce(::Type{T}, f, op, src::AbstractArray...; init, batch_size=default_batch_size(length(src[1]))) where T
    _tmapreduce(T, init, batch_size, f, op, src...)
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

"""
    getrange(n)

Partition the range `1:n` into `Threads.nthreads()` subranges and return the one corresponding to `Threads.threadid()`.
Useful for splitting a workload among multiple threads. See also the `TiledIteration` package for more advanced variants.
"""
function getrange(n)
    tid = Threads.threadid()
    nt = Threads.nthreads()
    d , r = divrem(n, nt)
    from = (tid - 1) * d + min(r, tid - 1) + 1
    to = from + d - 1 + (tid ≤ r ? 1 : 0)
    from:to
end

end
