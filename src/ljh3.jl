using JSON
import Base: ==

struct LJH3File{FramePeriod}
    io::IOStream
    index::Vector{Int} # points to the start of records, and potential next record
    header::OrderedDict{String,Any}
end
"""    LJH3File(fname::AbstractString)
Open an LJH3 file. Records can be accessed by indexing with integers like an `AbstractVector`,
eg `ljh[1]` or by iteration eg `collect(ljh)` or `for record in ljh dosomething() end`.
Due to the possibility of unequal record lengths, random access will be slow until
the file is fully indexed. Indexing occurs automatically whenever you access a record.
An `LJH3File` presents a dictionary like interface for accessing the header,
eg `ljh["File Format Version"]` or `keys(ljh)`. Use `frameperiod(ljh)` to get the
time between succesive samples in seconds."""
LJH3File(fname::AbstractString) = LJH3File(open(fname,"r"))
function LJH3File(io::IO; shouldseekstart=true)
    shouldseekstart && seekstart(io)
    header = JSON.parse(io, dicttype=OrderedDict)
    frameperiod = header["frameperiod"]
    @assert read(io, Char) == '\n'
    @assert header["File Format"]=="LJH3"
    @assert header["File Format Version"] == "3.0.0"
    LJH3File{frameperiod}(io,Int[position(io)], header)
end
frameperiod(ljh::LJH3File{FramePeriod}) where FramePeriod = FramePeriod
Base.close(ljh::LJH3File) = close(ljh.io)
filename(ljh::LJH3File) = ljh.io.name[7:end-1]
progresssize(ljh::LJH3File) = stat(ljh.io).size
progressposition(ljh::LJH3File) = position(ljh.io)
"    ljhopen(fname::AbstractString; kwargs...)
Open file `fname` as an `LJH3File` or `LJHFile` depending on contents."
function ljhopen(fname::AbstractString; kwargs...)
    try
        return LJH3File(fname; kwargs...)
    catch
        try
            return LJHFile(fname; kwargs...)
        catch
            error("$fname failed to open as LJH or LJH3")
        end
    end
end
"`LJH3Record` are returned when accessing a record in an `LJH3File`. Use functions
`data(r)`, `first_rising_sample(r)`, count(r)`, and `timestamp_usec(r)` to extract
information from a record `r`."
struct LJH3Record{FramePeriod}
    data::Vector{UInt16}
    first_rising_sample::Int32
    frame1index::Int64
    timestamp_usec::Int64
end
data(r::LJH3Record) = r.data
first_rising_sample(r::LJH3Record) = r.first_rising_sample
frame1index(r::LJH3Record) = r.frame1index
timestamp_usec(r::LJH3Record) = r.timestamp_usec
frameperiod(r::LJH3Record{FramePeriod}) where FramePeriod = FramePeriod
Base.length(r::LJH3Record) = length(r.data)
==(a::LJH3Record, b::LJH3Record) = a.data == b.data && a.first_rising_sample == b.first_rising_sample && a.frame1index == b.frame1index && a.timestamp_usec == b.timestamp_usec
"    write(ljh::LJH3File, trace::Vector{UInt16},first_rising_sample, frame1index::Int64, timestamp_usec::Int64)
Write a single record to `ljh`. Assumes `ljh.io` is at the same position it would be if you had
called `seekend(ljh.io)`."
function Base.write(ljh::LJH3File, trace::Vector{UInt16},first_rising_sample, frame1index::Int64, timestamp_usec::Int64)
    write(ljh.io, Int32(length(trace)), Int32(first_rising_sample), frame1index, timestamp_usec, trace)
    push!(ljh.index,position(ljh.io))
end
"""    create3(filename::AbstractString, frameperiod, header_extra = Dict();version="3.0.0")
Return an `LJH3File` ready for writing with `write`. The header will contain "frameperiod",
"File Format", "File Format Version" and any items in `header_extra`. Items in `header_extra`
will overwrite the header items passed as arguments, and you can make an invalid LJH3 file
this way. You are advised to avoid creating invalid LJH3 files.
"""
function create3(filename::AbstractString, frameperiod, header_extra = Dict();version="3.0.0")
    io = open(filename,"w+")
    header = OrderedDict{String,Any}()
    header["File Format"] = "LJH3"
    header["File Format Version"] = version
    header["frameperiod"]=frameperiod
    for (k,v) in header_extra
        header[k]=v
    end
    JSON.print(io, header, 4) # last argument uses pretty printing
    print(io,"\n")
    LJH3File(io)
end
function seekto(ljh::LJH3File, i::Int)
    if length(ljh.index) >= i
        @inbounds seek(ljh.io, ljh.index[i])
    else
        error("LJH3 Bounds Error")
    end
end
function _readrecord(ljh::LJH3File{FramePeriod},i) where FramePeriod
    num_samples = read(ljh.io, Int32)
    first_rising_sample = read(ljh.io, Int32)
    frame1index = read(ljh.io, Int64)
    timestamp_usec = read(ljh.io, Int64)
    data = Array{UInt16}(undef, num_samples)
    read!(ljh.io, data)
    if i==length(ljh.index)
        deltapos = 2*num_samples + 24
        @inbounds push!(ljh.index,ljh.index[i]+deltapos)
        # now, ljh.index[end] is the first unobserved byte offset into ljh.io
        # it may or may not be the start of a pulse
    end
    LJH3Record{FramePeriod}(data, first_rising_sample, frame1index, timestamp_usec)
end
function tryread(ljh::LJH3File{FramePeriod}) where FramePeriod
    d1 = read(ljh.io,4)
    if length(d1)<4
        seek(ljh.io, position(ljh.io)-length(d1)) # go back to the start of the record
        return Nullable{LJH3Record{FramePeriod}}()
    end
    num_samples = reinterpret(Int32,d1)[1]
    rest_of_record_length = 20+2*num_samples
    d2 = read(ljh.io,rest_of_record_length)
    if length(d2) < rest_of_record_length
        seek(ljh.io, position(ljh.io)-length(d1)-length(d2)) # go back to the start of the record
        return Nullable{LJH3ecord{FramePeriod}}()
    end
    first_rising_sample = reinterpret(Int32,d2[1:4])[1]
    frame1index = reinterpret(Int64,d2[5:12])[1]
    timestamp_usec = reinterpret(Int64,d2[13:20])[1]
    data = reinterpret(UInt16,d2[21:end])
    Nullable(LJH3Record{FramePeriod}(data,first_rising_sample, frame1index, timestamp_usec))
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
    nknown = length(ljh.index)
    state = nknown, stat(ljh.io).size
    seekto(ljh, nknown)
    next = Base.iterate(ljh, state)
    while next !== nothing
        (i, state) = next
        next = Base.iterate(ljh, state)
    end
    return length(ljh.index)-1
end
Base.lastindex(ljh::LJH3File) = length(ljh)
# iterator interface
function Base.iterate(ljh::LJH3File, state=nothing)
    if state == nothing
        seekto(ljh,1)
        state = 1, stat(ljh.io).size
    end
    j,sz = state
    if ljh.index[j] ≥ sz
        return nothing
    end
    _readrecord(ljh,j),(j+1,sz)
end
Base.IteratorSize(ljh::LJH3File) = Base.SizeUnknown()
# getindex with strings
Base.getindex(ljh::LJH3File,key::AbstractString) = ljh.header[key]
Base.keys(ljh::LJH3File) = keys(ljh.header)
Base.values(ljh::LJH3File) = values(ljh.header)
Base.eltype(ljh::LJH3File) = LJH3Record{frameperiod(ljh)}
