using ArgCheck
using OffsetArrays

export tmap, tmap!, tmapreduce, treduce

############################## docs ##############################
function _make_docstring(fname, args, kw=String[])
    tf = tname(Symbol(fname))
    sargs = join(args, ", ")
    skw = join([kw; "[batch_size::Integer]"], ", ")
    signature = string(tf, "(", sargs, "; ", skw, ")")
    """
        $signature

    Threaded analog of [`Base.$fname`](@ref). See [`Base.$fname`](@ref) for a description of arguments.
    In order to parallelize the arguments are split into chunks whose size in controlled by the `batch_size` keyword.
    """
end

function tname(s::Symbol)
    Symbol("t", s)
end

const SYMBOLS_MAPREDUCE_LIKE = [:sum, :prod, :minimum, :maximum]
for fun in SYMBOLS_MAPREDUCE_LIKE
    tfun = tname(fun)
    docstring = _make_docstring(fun, ["[f]", "src::AbstractArray"])
    @eval begin
        export $tfun
        @doc $docstring ->
        function $tfun end
    end
end

@doc _make_docstring(:map!, ["f", "dst::AbstractArray", "srcs::AbstractArray..."]) ->
function tmap! end

@doc _make_docstring(:map, ["f", "srcs::AbstractArray..."]) ->
function tmap end

@doc _make_docstring(:mapreduce, ["f", "op", "src::AbstractArray"], ["[init]"]) ->
function tmapreduce end

@doc _make_docstring(:reduce, ["op", "src::AbstractArray"],  ["[init]"]) ->
function treduce end

############################## Helper functions ##############################
struct Batches{V}
    firstindex::Int
    lastindex::Int
    batch_size::Int
    values::V
    length::Int
end

function Batches(values, batch_size::Integer)
    @argcheck batch_size > 0
    r = eachindex(values)
    @assert r isa AbstractUnitRange
    len = ceil(Int, length(r) / batch_size)
    Batches(first(r), last(r), batch_size, values, len)
end

Base.length(o::Batches) = o.length
Base.eachindex(o::Batches) = Base.OneTo(length(o))
function Base.getindex(o::Batches, i)
    @boundscheck (@argcheck i in eachindex(o))
    start = o.firstindex + (i-1) * o.batch_size
    stop  = min(start + (o.batch_size) -1, o.lastindex)
    o.values[start:stop]
end

function default_batch_size(len)
    len <= 1 && return 1
    nthreads=Threads.nthreads()
    items_per_thread = len/nthreads
    items_per_batch = items_per_thread/4
    max(1, round(Int, items_per_batch))
end

function Base.iterate(o::Batches, state=1)
    if state in eachindex(o)
        o[state], state+1
    else
        nothing
    end
end

mutable struct _MutableSubVector{T, A <: AbstractArray{T}, I <: AbstractUnitRange} <: AbstractVector{T}
    array::A
    eachindex::I
end

Base.size(r::_MutableSubVector) = (length(r.eachindex),)

lispy_allequal() = true
lispy_allequal(x) = true
lispy_allequal(x,y,rest...) = (x == y) && lispy_allequal(y, rest...)
allequal(itr) = lispy_allequal(itr...)

function Base.eachindex(r::_MutableSubVector, rs::_MutableSubVector...)
    @assert allequal(map(r -> r.eachindex, (r, rs...)))
    Base.IdentityUnitRange(r.eachindex)
end
Base.axes(r::_MutableSubVector) = (eachindex(r),)

@inline function Base.getindex(o::_MutableSubVector, i)
    @boundscheck checkbounds(o, i)
    @inbounds o.array[i]
end

@inline function Base.setindex!(o::_MutableSubVector, val, i)
    @boundscheck checkbounds(o, i)
    @inbounds o.array[i] = val
end

############################## tmap, tmap! ##############################
struct MapWorkspace{F,B,AD,AS}
    f::F
    batches::B
    arena_dst_view::AD
    arena_src_views::AS
end

@noinline function run!(o::MapWorkspace)
    # The @threads macro creates a closure. As of Julia 1.2 these are challenging to 
    # infer and the folloing let trick helps the compiler.
    # https://docs.julialang.org/en/v1.1.0/manual/performance-tips/#man-performance-captured-1
    let o=o
        Threads.@threads for i in 1:length(o.batches)
            tid = Threads.threadid()
            dst_view  = o.arena_dst_view[tid]
            src_views = o.arena_src_views[tid]
            inds = o.batches[i]
            dst_view.eachindex = inds
            let inds=inds
                foreach(src_views) do view
                    view.eachindex = inds
                end
            end
            Base.map!(o.f, dst_view, src_views...)
        end
    end
end

function create_arena_src_views(srcs, sample_inds)
    nt = Threads.nthreads()
    [Base.map(src -> _MutableSubVector(src, sample_inds), srcs) for _ in 1:nt]
end

@noinline function prepare(::typeof(tmap!), f, dst, srcs; batch_size::Int)
    # we use IndexLinear since _MutableSubVector implementation
    # does not support other indexing well
    all_inds  = eachindex(IndexLinear(), srcs...)
    batches   = Batches(all_inds, batch_size)
    sample_inds = batches[1]
    nt = Threads.nthreads()
    arena_dst_view  = [_MutableSubVector(dst, sample_inds) for _ in 1:nt]
    arena_src_views = create_arena_src_views(srcs, sample_inds)
    return MapWorkspace(f, batches, arena_dst_view, arena_src_views)
end

@noinline function tmap!(f, dst, srcs::AbstractArray...;
                        batch_size=default_batch_size(length(dst)))
    isempty(first(srcs)) && return dst
    w = prepare(tmap!, f, dst, srcs, batch_size=batch_size)
    run!(w)
    dst
end

function tmap(f, srcs::AbstractArray...; 
             batch_size=default_batch_size(length(first(srcs)))
            )
    g = Base.Generator(f,srcs...)
    T = Base.@default_eltype(g)
    dst = similar(first(srcs), T)
    tmap!(f, dst, srcs...; batch_size=batch_size)
end

############################## tmapreduce(like) ##############################
struct Reduction{O}
    op::O
end
(red::Reduction)(f, srcs...) = Base.mapreduce(f, red.op, srcs...)

struct MapReduceWorkspace{R,F,B,V,OA<:OffsetArray}
    reduction::R
    f::F
    batches::Batches{B}
    arena_src_views::V
    batch_reductions::OA
end

struct NoInit end

function create_reduction(::typeof(tmapreduce), op)
    Reduction(op)
end

function prepare(::typeof(tmapreduce), f, op, srcs; init, batch_size::Int)
    red = Reduction(op)
    w = prepare_mapreduce_like(red, f, srcs, init, batch_size=batch_size)
    return w
end

function tmapreduce(f, op, srcs::AbstractArray...;
                   init=NoInit(),
                   batch_size= default_batch_size(length(first(srcs)))
                  )
    if isempty(first(srcs))
        if init isa NoInit
            return Base.mapreduce(f, op, srcs...)
        else
            return Base.mapreduce(f, op, srcs..., init=init)
        end
    end
    w = prepare(tmapreduce, f, op, srcs, init=init, batch_size=batch_size)
    run!(w)
end

function treduce(op, srcs::AbstractArray...; kw...)
    tmapreduce(identity, op, srcs...; kw...)
end


for red in SYMBOLS_MAPREDUCE_LIKE
    tred = tname(red)
    @eval function $tred(f, src::AbstractArray;
                        batch_size=default_batch_size(length(src)))
        isempty(src) && return Base.$red(f, src)
        srcs = (src,)
        w = prepare($tred, f, srcs, batch_size=batch_size)
        run!(w)
    end
    @eval $tred(src; kw...) = $tred(identity, src; kw...)

    @eval function prepare(::typeof($tred), f, srcs; batch_size::Int)
        base_red = Base.$red
        prepare_mapreduce_like(base_red, f, srcs, batch_size=batch_size)
    end

end

function prepare_mapreduce_like(red, f, srcs, init=NoInit(); batch_size::Int)
    all_inds  = eachindex(IndexLinear(), srcs...)
    batches   = Batches(all_inds, batch_size)
    sample_inds = batches[1]

    arena_src_views = create_arena_src_views(srcs, sample_inds)
    T = get_return_type(red, f, srcs)

    if (init isa NoInit)
        batch_reductions = OffsetVector{T}(undef, 1:length(batches))
    else
        batch_reductions = OffsetVector{T}(undef, 0:length(batches))
        batch_reductions[0] = init
    end
    MapReduceWorkspace(red, f, batches, arena_src_views, batch_reductions)
end

@inline function get_return_type(red, f, srcs)
    Core.Compiler.return_type(red, Tuple{typeof(f), typeof.(srcs)...})
end

@noinline function run!(o::MapReduceWorkspace)
    Threads.@threads for i in 1:length(o.batches)
        tid = Threads.threadid()
        src_views = o.arena_src_views[tid]
        inds = o.batches[i]
        for src_view in src_views
            src_view.eachindex = inds
        end
        o.batch_reductions[i] = o.reduction(o.f, src_views...)
    end
    o.reduction(identity, o.batch_reductions)
end
