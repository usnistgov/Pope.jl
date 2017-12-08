using JSON

mutable struct LJH3File
    io::IO
    index::Vector{Int} # 1 more than number of records
    furthestread::Int
    frametime::Float64
    header::OrderedDict{String,Any}
end
LJH3File(fname::AbstractString) = LJH3File(open(fname,"r"))
function LJH3File(io::IO; shouldseekstart=true)
    shouldseekstart && seekstart(io)
    header = JSON.parse(io, dicttype=OrderedDict)
    frametime = header["frametime"]
    @assert header["File Format"]=="LJH3"
    @assert header["File Format Version"] == "3.0.0"
    LJH3File(io,Int[position(io)],position(io),frametime, header)
end
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
function create3(filename::AbstractString, frametime, dict_in = Dict();version="3.0.0")
    io = open(filename,"w+")
    d = OrderedDict{String,Any}()
    d["File Format"] = "LJH3"
    d["File Format Version"] = version
    d["frametime"]=frametime
    for (k,v) in dict_in
        d[k]=v
    end
    JSON.print(io, d)
    LJH3File(io)
end

function seekto(f::LJH3File, i::Int)
    if length(f.index) >= i
        @inbounds seek(f.io, f.index[i])
    else
        error("LJH3 Bounds Error")
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
function index!(ljh::LJH3File)
    if stat(ljh.io).size > ljh.furthestread
        collect(ljh)
    end
    return nothing
end
function ljh_number_of_records(ljh::LJH3File)
    index!(ljh)
    return length(ljh.index)-1
end
# Array interface
Base.size(f::LJH3File) = (ljh_number_of_records(f),)
Base.length(f::LJH3File) = ljh_number_of_records(f)
Base.endof(f::LJH3File) = ljh_number_of_records(f)
# iterator interface
Base.start(f::LJH3File) = (seekto(f,1);1)
Base.next(f::LJH3File,j) = pop!(f),j+1
Base.done(f::LJH3File,j) = f.furthestread==stat(f.io).size
Base.iteratorsize(ljh::LJH3File) = Base.SizeUnknown()
# getindex with strings
Base.getindex(ljh::LJH3File,key::AbstractString) = ljh.header[key]
Base.keys(ljh::LJH3File) = keys(ljh.header)
Base.values(ljh::LJH3File) = values(ljh.header)
