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
function create3(filename::AbstractString, frametime, header_extra = Dict();version="3.0.0")
    io = open(filename,"w+")
    header = OrderedDict{String,Any}()
    header["File Format"] = "LJH3"
    header["File Format Version"] = version
    header["frametime"]=frametime
    for (k,v) in header_extra
        header[k]=v
    end
    JSON.print(io, header)
    LJH3File(io)
end
function seekto(ljh::LJH3File, i::Int)
    if length(ljh.index) >= i
        @inbounds seek(ljh.io, ljh.index[i])
    else
        error("LJH3 Bounds Error")
    end
end
function Base.pop!(ljh::LJH3File)
    trace_samples = read(ljh.io, UInt32)
    first_rising_sample = read(ljh.io, UInt32)
    rowcount = read(ljh.io, Int64)
    timestamp_usec = read(ljh.io, Int64)
    data = read(ljh.io, UInt16, trace_samples)
    pos = position(ljh.io)
    if pos>ljh.furthestread
        ljh.furthestread=pos
        push!(ljh.index,pos)
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
function Base.getindex(ljh::LJH3File,index::Int)
    seekto(ljh, index)
    pop!(ljh)
end
Base.size(ljh::LJH3File) = (ljh_number_of_records(ljh),)
Base.length(ljh::LJH3File) = ljh_number_of_records(ljh)
Base.endof(ljh::LJH3File) = ljh_number_of_records(ljh)
# iterator interface
Base.start(ljh::LJH3File) = (seekto(ljh,1);1)
Base.next(ljh::LJH3File,j) = pop!(ljh),j+1
Base.done(ljh::LJH3File,j) = ljh.furthestread==stat(ljh.io).size
Base.iteratorsize(ljh::LJH3File) = Base.SizeUnknown()
# getindex with strings
Base.getindex(ljh::LJH3File,key::AbstractString) = ljh.header[key]
Base.keys(ljh::LJH3File) = keys(ljh.header)
Base.values(ljh::LJH3File) = values(ljh.header)
