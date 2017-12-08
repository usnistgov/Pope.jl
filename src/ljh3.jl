mutable struct LJH3File
    io::IO
    index::Vector{Int}
    furthestread::Int
end
LJH3File(fname::AbstractString) = LJH3File(seekstart(open(fname,"r")),Int[0],0)
struct LJH3Record
    data::Vector{UInt16}
    first_rising_sample::UInt32
    rowcount::Int64
    timestamp_usec::Int64
end
data(r::LJH3Record) = r.data
rowcount(r::LJH3Record) = r.rowcount
timestamp_usec(r::LJH3Record) = r.timestamp_usec

Base.close(ljh::LJH3File) = close(ljh.io)
function Base.write(ljh::LJH3File, trace::Vector{UInt16},first_rising_sample, rowcount::Int64, timestamp_usec::Int64)
    write(ljh.io, UInt32(length(trace)), UInt32(first_rising_sample), rowcount, timestamp_usec, trace)
end
function create3(filename::AbstractString)
    f = open(filename,"w+")
    LJH3File(f,Int[],0)
end

function seekto(f::LJH3File, i::Int)
    if length(f.index) >= i
        @inbounds seek(f.io, f.index[i])
    else
        error("not in index, but could it be in file?")
    end
end
function Base.getindex(f::LJH3File,index::Int)
    seekto(f, index)
    pop!(f)
end
function Base.pop!(f::LJH3File)
    trace_samples = read(f.io, UInt32)
    first_rising_sample = read(f.io, UInt32)
    rowcount = read(f.io, Int64)
    timestamp_usec = read(f.io, Int64)
    data = read(f.io, UInt16, trace_samples)
    pos = position(f.io)
    if pos>f.furthestread
        f.furthestread=pos
        push!(f.index,pos)
    end
    LJH3Record(data, first_rising_sample, rowcount, timestamp_usec)
end
function ljh_number_of_records(ljh::LJH3File)
    if ljh.furthestread == stat(ljh.io).size
        length(ljh.index)-1
    else
        collect(ljh) # collect will force it to index, this could be faster
        if ljh.furthestread == stat(ljh.io).size
            length(ljh.index)-1
        else
            error("fail")
        end
    end
end
Base.size(f::LJH3File) = (ljh_number_of_records(f),)
Base.length(f::LJH3File) = ljh_number_of_records(f)
Base.endof(f::LJH3File) = ljh_number_of_records(f)
# access as iterator
Base.start(f::LJH3File) = (seekto(f,1);1)
Base.next(f::LJH3File,j) = pop!(f),j+1
Base.done(f::LJH3File,j) = f.furthestread==stat(f.io).size
Base.iteratorsize(ljh::LJH3File) = Base.SizeUnknown()
