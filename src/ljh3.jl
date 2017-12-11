using JSON
import Base: ==

struct LJH3File
    io::IOStream
    index::Vector{Int} # points to the start of records, and potential next record
    sampleperiod::Float64
    header::OrderedDict{String,Any}
end
LJH3File(fname::AbstractString) = LJH3File(open(fname,"r"))
function LJH3File(io::IO; shouldseekstart=true)
    shouldseekstart && seekstart(io)
    header = JSON.parse(io, dicttype=OrderedDict)
    sampleperiod = header["sampleperiod"]
    @assert header["File Format"]=="LJH3"
    @assert header["File Format Version"] == "3.0.0"
    LJH3File(io,Int[position(io)],sampleperiod, header)
end
struct LJH3Record
    data::Vector{UInt16}
    first_rising_sample::UInt32
    samplecount::Int64
    timestamp_usec::Int64
end
data(r::LJH3Record) = r.data
samplecount(r::LJH3Record) = r.samplecount
timestamp_usec(r::LJH3Record) = r.timestamp_usec

==(a::LJH3Record, b::LJH3Record) = a.data == b.data && a.first_rising_sample == b.first_rising_sample && a.samplecount == b.samplecount && a.timestamp_usec == b.timestamp_usec
Base.close(ljh::LJH3File) = close(ljh.io)
function Base.write(ljh::LJH3File, trace::Vector{UInt16},first_rising_sample, samplecount::Int64, timestamp_usec::Int64)
    write(ljh.io, UInt32(length(trace)), UInt32(first_rising_sample), samplecount, timestamp_usec, trace)
    push!(ljh.index,position(ljh.io))
end
function create3(filename::AbstractString, sampleperiod, header_extra = Dict();version="3.0.0")
    io = open(filename,"w+")
    header = OrderedDict{String,Any}()
    header["File Format"] = "LJH3"
    header["File Format Version"] = version
    header["sampleperiod"]=sampleperiod
    for (k,v) in header_extra
        header[k]=v
    end
    JSON.print(io, header, 4) # last argument uses pretty printing
    LJH3File(io)
end
function seekto(ljh::LJH3File, i::Int)
    if length(ljh.index) >= i
        @inbounds seek(ljh.io, ljh.index[i])
    else
        error("LJH3 Bounds Error")
    end
end
function _readrecord(ljh::LJH3File,i)
    num_samples = read(ljh.io, UInt32)
    first_rising_sample = read(ljh.io, UInt32)
    samplecount = read(ljh.io, Int64)
    timestamp_usec = read(ljh.io, Int64)
    data = read(ljh.io, UInt16, num_samples)
    if i==length(ljh.index)
        deltapos = 2*num_samples + 24
        @inbounds push!(ljh.index,ljh.index[i]+deltapos)
        # now, ljh.index[end] is the first unobserved byte offset into ljh.io
        # it may or may not be the start of a pulse
    end
    LJH3Record(data, first_rising_sample, samplecount, timestamp_usec)
end
function tryread(ljh::LJH3File)
    d1 = read(ljh.io,4)
    if length(d1)<4
        seek(ljh.io, position(ljh.io)-length(d1)) # go back to the start of the record
        return Nullable{LJH3Record}()
    end
    num_samples = reinterpret(UInt32,d1)[1]
    rest_of_record_length = 20+2*num_samples
    d2 = read(ljh.io,rest_of_record_length)
    if length(d2) < rest_of_record_length
        seek(ljh.io, position(ljh.io)-length(d1)-length(d2)) # go back to the start of the record
        return Nullable{LJH3ecord}()
    end
    first_rising_sample = reinterpret(UInt32,d2[1:4])[1]
    samplecount = reinterpret(Int64,d2[5:12])[1]
    timestamp_usec = reinterpret(Int64,d2[13:20])[1]
    data = reinterpret(UInt16,d2[21:end])
    Nullable(LJH3Record(data,first_rising_sample, samplecount, timestamp_usec))
end
# Array interface
function Base.getindex(ljh::LJH3File,i::Int)
    seekto(ljh, i)
    _readrecord(ljh,i)
end
Base.size(ljh::LJH3File) = (length(ljh),)
function Base.length(ljh::LJH3File)
    # iterate from the last entry in index to the end of the file
    # to fill ljh.index
    state = length(ljh.index), stat(ljh.io).size
    while !done(ljh,state)
        _,state = next(ljh,state)
    end
    return length(ljh.index)-1
end
Base.endof(ljh::LJH3File) = length(ljh)
# iterator interface
Base.start(ljh::LJH3File) = (seekto(ljh,1);(1,stat(ljh.io).size))
function Base.next(ljh::LJH3File,state)
    j,sz=state
    _readrecord(ljh,j),(j+1,sz)
end
function Base.done(ljh::LJH3File,state)
    j,sz=state
    ljh.index[j]==sz
end
Base.iteratorsize(ljh::LJH3File) = Base.SizeUnknown()
# getindex with strings
Base.getindex(ljh::LJH3File,key::AbstractString) = ljh.header[key]
Base.keys(ljh::LJH3File) = keys(ljh.header)
Base.values(ljh::LJH3File) = values(ljh.header)
