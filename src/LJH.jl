module LJH
export LJHGroup, LJHFile, LJH3File, ljhopen
include("ljhutil.jl")
using Nullables

"    ljh_get_header_dict(io::IO)
Return a Dict{String,String} mapping entries in the header. "
function ljh_get_header_dict(io::IO)
    headerdict = Dict()
    while true
        line = readline(io)
        if startswith(line, "#End of Header")
            break
        elseif eof(io)
          error("eof while reading header")
        elseif startswith(line, "#")
            continue
        else
            splitline=split(line,":")
            if length(splitline) != 2
              continue
            end
            a,b = splitline
            headerdict[strip(a)]=strip(b)
        end
    end
    headerdict
end

mutable struct LJHFile{VersionInt, FrameTime, PretrigNSamples, NRow, T<:IO}
    filename         ::String           # filename
    io               ::IO               # IO to read from LJH file
    headerdict       ::Dict             # LJH file header data
    datastartpos     ::Int
    record_nsamples  ::Int64            # number of sample per record
    channum          ::Int16            # channel number
    column           ::Int16            # column number
    row              ::Int16            # row number
    num_columns      ::Int16            # number of rows
    inverted_data    ::Bool             # data values inverted (downward-going pulses)?
end
struct LJHRecord{FrameTime, PretrigNSamples, NRow}
    data::Vector{UInt16}
    rowcount::Int64
    timestamp_usec::Int64
end
data(r::LJHRecord) = r.data
rowcount(r::LJHRecord) = r.rowcount
timestamp_usec(r::LJHRecord) = r.timestamp_usec
num_rows(r::LJHRecord{FrameTime, PretrigNSamples, NRow}) where {FrameTime, PretrigNSamples, NRow} = NRow
frametime(r::LJHRecord{FrameTime, PretrigNSamples, NRow}) where {FrameTime, PretrigNSamples, NRow} = FrameTime
frame1index(r::LJHRecord{FrameTime, PretrigNSamples, NRow}) where {FrameTime, PretrigNSamples, NRow} = div(rowcount(r), num_rows(r))
first_rising_sample(r::LJHRecord{FrameTime, PretrigNSamples, NRow}) where {FrameTime, PretrigNSamples, NRow} = PretrigNSamples
frameperiod(r::LJHRecord) = frametime(r)

Base.length(r::LJHRecord) = length(r.data)
import Base: ==
==(a::LJHRecord, b::LJHRecord) = a.data==b.data && a.rowcount == b.rowcount && a.timestamp_usec == b.timestamp_usec

@enum LJHVERSION LJH_20 LJH_21 LJH_22
VERSIONS = Dict(v"2.0.0"=>LJH_20, v"2.1.0"=>LJH_21, v"2.2.0"=>LJH_22,
v"2.2.1"=>LJH_22)

LJHFile(fname::String; inverted=false) = LJHFile(fname, open(fname,"r"); inverted=inverted)
function LJHFile(fname::String, io::IO; inverted=false)
    headerdict = ljh_get_header_dict(seekstart(io))
    datastartpos = position(io)
    # ioend = position(seekend(io))
    ioend = stat(io).size
    # seek(io,datastartpos)
    version = VersionNumber(headerdict["Save File Format Version"])
    version in keys(VERSIONS) || error("$fname has version $version, which is not in VERSIONS $VERSIONS")
    versionint = VERSIONS[version]
    record_nsamples = parse(Int,headerdict["Total Samples"])
    NRow = parse(Int16, get(headerdict,"Number of rows","1"))
    num_columns = parse(Int16, get(headerdict,"Number of columns","0"))
    FrameTime = parse(Float64,headerdict["Timebase"]) # frametime
    PretrigNSamples = parse(Int16,headerdict["Presamples"]) # pretrig_nsamples
    LJHFile{versionint, FrameTime, PretrigNSamples, NRow, typeof(io)}(
        fname, # filename
        io, # IO
        headerdict, #headerdict
        datastartpos, # datastartpos
        parse(Int16,headerdict["Total Samples"]), # record_nsamples
        round(Int16,parse(Float64,headerdict["Channel"])), # channel number
        parse(Int16,get(headerdict,"Column number (from 0-$(num_columns-1) inclusive)","0")),   #column, defaults to zero if not in file
        parse(Int16,get(headerdict,"Row number (from 0-$(NRow-1) inclusive)","0")), #row, defaults to zero if not in file
        num_columns,
        inverted)
end
LJHFile(f::LJHFile) = f

"header_nbytes(f::LJHFile)
    Return number of bytes in the header of each record in LJH file, based on version number"
header_nbytes(f::LJHFile{LJH_20}) = 6
header_nbytes(f::LJHFile{LJH_21}) = 6
header_nbytes(f::LJHFile{LJH_22}) = 16

"record_nbytes(f::LJHFile)
    Return number of bytes per record in LJH file, based on version number"
record_nbytes(f::LJHFile) = header_nbytes(f)+2*f.record_nsamples

"    ljh_number_of_records(f::LJHFile)
Return the number of complete records currently available to read from `f`."
function ljh_number_of_records(f::LJHFile)
    nbytes = stat(f.io).size-f.datastartpos
    number_of_records = div(nbytes, record_nbytes(f))
end

"    progresssize(f::Union{LJHFile, LJH3File)
Return the value that `progressposition` will return when the file is at `seekend(f.io)`.
Used to allow `ProgressBar` to work for both `LJHFile` and `LJH3File`."
progresssize(f::LJHFile) = length(f)
"    progressposition(f::LJHFile)
Return a value to pass to `update!(p::ProgressBar,position)`. Used to allow
`ProgressBar` to work for both `LJHFile` and `LJH3File`."
progressposition(f::LJHFile) = div(position(f.io)-f.datastartpos,record_nbytes(f))

# support for ljhfile[1:7] syntax
seekto(f::LJHFile, i::Int) = seek(f.io,f.datastartpos+(i-1)*record_nbytes(f))
Base.getindex(f::LJHFile,indexes::AbstractVector)=LJHGroupSlice(LJHGroup(f), indexes)
function Base.getindex(f::LJHFile,index::Int)
    seekto(f, index)
    pop!(f)
end
Base.pop!(f::LJHFile) = get(tryread(f)) # use get to raise error if Nullable is null.
_readrecord(f::LJHFile,i) = pop!(f)

Base.size(f::LJHFile) = (ljh_number_of_records(f),)
Base.length(f::LJHFile) = ljh_number_of_records(f)
Base.endof(f::LJHFile) = ljh_number_of_records(f)
function Base.eltype(f::LJHFile{V, FrameTime, PretrigNSamples, NRow}) where {V, FrameTime, PretrigNSamples, NRow}
     LJHRecord{FrameTime, PretrigNSamples, NRow}
end
# access as iterator
Base.start(f::LJHFile) = (seekto(f,1);1)
Base.next(f::LJHFile,j) = pop!(f),j+1
Base.done(f::LJHFile,j) = j==length(f)+1
filename(f::LJHFile) = f.filename
record_nsamples(f::LJHFile) = f.record_nsamples
function pretrig_nsamples(f::LJHFile{VersionInt, FrameTime, PretrigNSamples, NRow}) where {VersionInt, FrameTime, PretrigNSamples, NRow}
    convert(Int,PretrigNSamples)
end
channel(f::LJHFile) = f.channum
row(f::LJHFile) = f.row
column(f::LJHFile) = f.column
function frameperiod(f::LJHFile{VersionInt, FrameTime, PretrigNSamples, NRow}) where {VersionInt, FrameTime, PretrigNSamples, NRow}
    convert(Float64, FrameTime)
end
frametime(f::LJHFile) = frameperiod(f)
function num_rows(f::LJHFile{VersionInt, FrameTime, PretrigNSamples, NRow}) where {VersionInt, FrameTime, PretrigNSamples, NRow}
    convert(Int, NRow)
end
function Base.show(io::IO, g::LJHFile)
    print(io, "LJHFile $(filename(g))\n")
    inverted = ""
    if g.inverted_data
        inverted = "inverted "
    end
    print(io, "$(length(g)) $(inverted)records\n")
    print(io, "record_nsamples $(record_nsamples(g)), pretrig_nsamples $(pretrig_nsamples(g)).\n")
    print(io, "Channel $(channel(g)), row $(row(g)), column $(column(g)), frametime $(frametime(g)) s.\n")
end

# open and close
Base.close(f::LJHFile) = close(f.io)

"""
    tryread{T}(f::LJHFile)

Attempt to read an `LJHRecord` from `f`. Return a `Nullable{LJHRecord}` containing
that record if succesful, or one that `isnull` if not. On success the file position
moves forward, on failure the file position does not change.
"""
function tryread(f::LJHFile{LJHv, FrameTime, PretrigNSamples, NRow}) where {LJHv, FrameTime, PretrigNSamples, NRow}
    nbytes = record_nbytes(f)
    record = read(f.io, nbytes)
    if length(record) == nbytes
        rowcount, timestamp_usec = parse_record_header(f, record)
        data = reinterpret(UInt16, record[1+header_nbytes(f):nbytes])
        if f.inverted_data
            data = .~data
        end
        return Nullable(LJHRecord{FrameTime, PretrigNSamples, NRow}(data, rowcount, timestamp_usec))
    else
        seek(f.io, position(f.io)-length(record)) # go back to the start of the record
        return Nullable{LJHRecord{FrameTime, PretrigNSamples, NRow}}()
    end
end
# this version with nb_available seems like it should work, and possibly be
# more performant, but nb_available doesn't seem to work as I expect
# function tryread{T}(f::LJHFile{LJH_22,T})
#   n = nb_available(f.io)
#   if n<record_nbytes(f)
#     return Nullable{LJHRecord}()
#   else
#     rowcount = read(Int,f.io)
#     timestamp_usec = read(Int,f.io)
#     data = read(UInt16, f.io, f.record_nsamples)
#     return Nullable(LJHRecord(data, rowcount, timestamp_usec))
#   end
# end

function parse_record_header(f::LJHFile{LJH_22}, record::Vector{UInt8})
    rowcount = reinterpret(Int, record[1:8])[1]
    timestamp_usec = reinterpret(Int, record[9:16])[1]
    rowcount, timestamp_usec
end

# Used only for reading LJH version 2.1.0 files. This parses the ugly
# "encoded" version of the frame counter, which is converted into an
# approximate time, rounded to 4 microseconds, and divided into the integer
# and fractional parts of the millisecond. The latter are stored in bytes
# 3-6, and the former is in byte 1. Ignore byte 2 (it has some need to be
# 0 for backward compatibility). Ugly! That's why LJH 2.2.0 does something
# totally different.
function parse_record_header(f::LJHFile{LJH_21}, record::Vector{UInt8})
    frac = Int64(record[1])
    ms = UInt64(record[3]) |
         (UInt64(record[4])<<8) |
         (UInt64(record[5])<<16) |
         (UInt64(record[6])<<24)
    count_4usec = Int64(250ms+frac)
    ns_per_frame = round(Int64, frametime(f)*1e9)
    ns_per_4usec = Int64(4000)
    count_nsec = count_4usec*ns_per_4usec
    count_frame = cld(count_nsec, ns_per_frame)
    rowcount = count_frame*num_rows(f)+f.row
    return rowcount, 4*count_4usec
end

# Used only for reading LJH version 2.0.0 files. This parses the ugly
# "encoded" version of the frame counter, which is converted into an
# approximate time, rounded to the nearest millisecond and stored in bytes
# 3-6. Ignore bytes 1-2 (they have some need to be
# 0 for backward compatibility).
function parse_record_header(f::LJHFile{LJH_20}, record::Vector{UInt8})
    ms = UInt64(record[3]) |
         (UInt64(record[4])<<8) |
         (UInt64(record[5])<<16) |
         (UInt64(record[6])<<24)
    ns_per_frame = round(Int64, frametime(f)*1e9)
    ns_per_msec = Int64(1000000)
    count_nsec = ms*ns_per_msec
    count_frame = cld(count_nsec, ns_per_frame)
    rowcount = count_frame*num_rows(f)+f.row
    return rowcount, 1000*ms
end

watch_file(f::LJHFile, timeout_s::Real) = watch_file(f.filename, timeout_s)


"""Represent one or more LJHFiles as a seamless sequence that can be addressed
by record number from 1 to the sum of all records in the group."""
mutable struct LJHGroup
    ljhfiles::Vector{LJHFile}
    lengths::Vector{Int}
end
function LJHGroup(x::Vector)
    ljhfiles = LJHFile[LJHFile(f) for f in x]
    LJHGroup(ljhfiles, [length(f) for f in ljhfiles])
end
LJHGroup(x::LJHFile) = LJHGroup(LJHFile[x])
LJHGroup(x::String) = LJHGroup(LJHFile(x))
Base.length(g::LJHGroup) = sum(g.lengths)
Base.close(g::LJHGroup) = map(close, g.ljhfiles)
Base.open(g::LJHGroup) = map(open, g.ljhfiles)
fieldvalue(g::LJHGroup, s::Symbol) = unique([getfield(f, s) for f in g.ljhfiles])
channel(g::LJHGroup) = (assert(length(fieldvalue(g, :channum))==1);g.ljhfiles[1].channum)
record_nsamples(g::LJHGroup) = (assert(length(fieldvalue(g, :record_nsamples))==1);g.ljhfiles[1].record_nsamples)
pretrig_nsamples(g::LJHGroup) = (assert(length(unique(pretrig_nsamples.(g.ljhfiles)))==1);pretrig_nsamples(g.ljhfiles[1]))
frametime(g::LJHGroup) = (assert(length(unique(frametime.(g.ljhfiles)))==1);frametime(g.ljhfiles[1]))
column(g::LJHGroup) = (assert(length(fieldvalue(g, :column))==1);g.ljhfiles[1].column)
row(g::LJHGroup) = (assert(length(fieldvalue(g, :row))==1);g.ljhfiles[1].row)
num_columns(g::LJHGroup) = (assert(length(fieldvalue(g, :num_columns))==1);g.ljhfiles[1].num_columns)
num_rows(g::LJHGroup) = (assert(length(unique(num_rows.(g.ljhfiles)))==1);num_rows(g.ljhfiles[1]))
filenames(g::LJHGroup) = [f.filename for f in g.ljhfiles]
lengths(g::LJHGroup) = g.lengths
"    watch(g::LJHGroup, timeout_s)
calls `watch_file` on the last LJH file in `g`, passes `timeout_s` through."
watch(g::LJHGroup, timeout_s) = watch_file(last(g.ljhfiles).filename, timeout_s)
"    update_num_records(g::LJHGroup)
examine the underlying LJHFiles to determine if any grew. If the last one grew, update `g.lengths`, otherwise throw an error"
function update_num_records(g::LJHGroup)
    old_lengths = copy(g.lengths)
    new_lengths = Int[length(f) for f in g.ljhfiles]
    for i = 1:length(g.lengths)-1
        if old_lengths[i]!=new_lengths[i]
            error("a ljh file other than the last file in grew in length $g it was $(g.ljhfiles[i])")
        end
    end
    g.lengths=new_lengths
end
"    filenum_recordnum(g::LJHGroup, j::Int)
The record `g[j]` is actually `g.ljhfiles[i][k]`, return `i,k`."
function filenum_recordnum(g::LJHGroup, j::Int)
    for (i,len) in enumerate(g.lengths)
        j <= len ? (return i,j) : (j-=len)
    end
    1,1 # default return value in case of empty range
end
function Base.getindex(g::LJHGroup, i::Int)
    filenum, recordnum = filenum_recordnum(g,i)
    g.ljhfiles[filenum][recordnum]
end
Base.getindex(g::LJHGroup, slice::AbstractArray) = LJHGroupSlice(g, slice)
Base.endof(g::LJHGroup) = length(g)
function Base.start(g::LJHGroup)
    for f in g.ljhfiles seekto(f,1) end
    filenum, recordnum = filenum_recordnum(g,1)
    donefilenum, donerecordnum = filenum_recordnum(g, length(g))
    (filenum, recordnum, donefilenum, donerecordnum)
end
function Base.next(g::LJHGroup, state)
    filenum, recordnum, donefilenum, donerecordnum = state
    ljhrecord = pop!(g.ljhfiles[filenum])
    recordnum+=1
    recordnum > g.lengths[filenum] && (recordnum-=g.lengths[filenum];filenum+=1)
    ljhrecord, (filenum, recordnum, donefilenum, donerecordnum)
end
function Base.done(g::LJHGroup, state)
    filenum, recordnum, donefilenum, donerecordnum = state
    filenum>donefilenum || filenum==donefilenum && recordnum>donerecordnum
end
function Base.show(io::IO, g::LJHGroup)
    print(io, "LJHGroup with $(length(g.ljhfiles)) files, $(length(g)) records, split as $(lengths(g)),")
    print(io, "record_nsampes $(record_nsamples(g)),\n")
    print(io, "pretrig_nsamples $(pretrig_nsamples(g)).")
    print(io, "channel $(channel(g)), row $(row(g)), column $(column(g)), frametime $(frametime(g)) s.\n")
    print(io, "First filename $(g.ljhfiles[1].filename)")
end



"`LJHGroupSlice` is used to allow acces to ranges of LJH records, eg `[r.data for r in ljh[1:100]]`."
struct LJHGroupSlice{T<:AbstractArray}
    g::LJHGroup
    slice::T
    function LJHGroupSlice{T}(ljhgroup, slice) where T
        isempty(slice) || maximum(slice)<=length(ljhgroup) || error("$(maximum(slice)) is greater than nrec=$(length(ljhgroup)) in $ljhgroup")
        new(ljhgroup, slice)
    end
end
Base.length(g::LJHGroupSlice) = length(g.slice)
Base.endof(g::LJHGroupSlice) = length(g.slice)
LJHGroupSlice(ljhfile::LJHGroup, slice::T) where T <: AbstractArray = LJHGroupSlice{T}(ljhfile, slice)
function Base.start(g::LJHGroupSlice{T}) where T <: UnitRange
    for f in g.g.ljhfiles seekto(f,1) end
    isempty(g.slice) && return (2,2,1,1) # ensure done condition is immediatley met on empty range
    filenum, recordnum = filenum_recordnum(g.g, first(g.slice))
    donefilenum, donerecordnum = filenum_recordnum(g.g, last(g.slice))
    seekto(g.g.ljhfiles[filenum], recordnum)
    (filenum, recordnum, donefilenum, donerecordnum)
end
function Base.next(g::LJHGroupSlice{T}, state) where T <: UnitRange
    filenum, recordnum, donefilenum, donerecordnum = state
    ljhrecord = pop!(g.g.ljhfiles[filenum])
    recordnum+=1
    recordnum > g.g.lengths[filenum] && (recordnum-=g.g.lengths[filenum];filenum+=1)
    ljhrecord, (filenum, recordnum, donefilenum, donerecordnum)
end
function Base.done(g::LJHGroupSlice{T}, state) where T <: UnitRange
    filenum, recordnum, donefilenum, donerecordnum = state
    filenum>donefilenum || filenum==donefilenum && recordnum>donerecordnum
end
record_nsamples(s::LJHGroupSlice) = record_nsamples(s.g)

const LJHLike = Union{LJHFile, LJHGroup, LJHGroupSlice}
"    get_data_rowcount_timestamp(g::LJHGroup)
Get all data from an `LJHGroup`, returned as a tuple of Vectors `(data, rowcount, timestamp_usec)`."
function get_data_rowcount_timestamp(g::LJHLike)
    data = Matrix{UInt16}(record_nsamples(g),length(g))
    rowcount = zeros(Int64, length(g))
    timestamp_usec = zeros(Int64, length(g))
    get_data_rowcount_timestamp!(g,data,rowcount,timestamp_usec)
end
"    get_data_rowcount_timestamp!(g::LJHGroupSlice),data::Matrix{UInt16},rowcount::Vector{Int64},timestamp_usec::Vector{Int64})
Get all data from an `LJHGroupSlice`, pass in vectors of length `length(g)` and correct type to be filled with the answers."
function get_data_rowcount_timestamp!(g::LJHLike,data::Matrix{UInt16},rowcount::Vector{Int64},timestamp_usec::Vector{Int64})
    state = start(g)
    i=0
    @assert size(data,2)==length(rowcount)==length(timestamp_usec)==length(g) "data, rowcount, timestap_usec: length mismatch: lengths $((size(data,2), length(rowcount), length(timestamp_usec), length(g)))"
    while !done(g, state)
        i+=1
        record, state = next(g,state)
        data[:,i] = record.data
        rowcount[i] = record.rowcount
        timestamp_usec[i] = record.timestamp_usec
    end
    @assert i==length(g) "iterated $i times, should have been $(length(g))"
    data,rowcount,timestamp_usec
end

function finalize_longrecord!(longrecords, records, nsamples)
    v = Vector{UInt16}(nsamples)
    i=1
    lasti=1
    for record in records
        ilast = min(i+length(record)-1, length(v))
        v[i:ilast] = data(record)[1:(ilast-i+1)]
        i=ilast+1
    end
    longrecord = LJH3Record{frameperiod(first(records))}(
        v,
        first_rising_sample(first(records)),
        frame1index(first(records)),
        timestamp_usec(first(records))
    )
    empty!(records)
    push!(longrecords, longrecord)
end


"""
     read_longrecords(ljh::LJHLike, nsamples;maxrecords=1, allowdiscontinuity=true, unevenfinalrecord=!allowdiscontinuity)

Return a `Vector{LJH3Record}` of at most `maxrecords` length, containing longrecords each with
`nsamples` samples. If `allowdiscontinuity` is `true`, each longrecord will have exactly `nsamples`
samples, even if the records in `ljh` were not continuous. If `allowdiscontinuity` is `false`
longrecords will have fewer samples when a gap between records in `ljh` exists. If `unevenfinalrecord` is `true`
the last returned longrecord may have fewer samples than `nsamples`, because `ljh` did not have enough
data for a full length longrecord.
"""
function read_longrecords(ljh::LJHLike, nsamples;maxrecords=1, allowdiscontinuity=true, unevenfinalrecord=!allowdiscontinuity)
    records = eltype(ljh)[] # records to be collated into a longrecord
    longrecords = LJH3Record{frameperiod(ljh)}[]
    for (i,record) in enumerate(ljh)
        if !isempty(records) && !allowdiscontinuity
            lastrec = last(records)
            if frame1index(record) != frame1index(lastrec)+length(lastrec)
                finalize_longrecord!(longrecords, records,sum(length.(records)))
                if length(longrecords)>=maxrecords
                    break
                end
                continue
            end
        end
        push!(records,record)
        if sum(length.(records)) >= nsamples
            finalize_longrecord!(longrecords, records, nsamples)
        end
        if length(longrecords)>=maxrecords
            break
        end
    end
    if !isempty(records) && length(longrecords) < maxrecords
        avail_nsamples = sum(length.(records))
        if avail_nsamples > nsamples || unevenfinalrecord
            finalize_longrecord!(longrecords, records,min(nsamples, avail_nsamples))
        end
    end
    return longrecords
end


"""
    create(filename::AbstractString, dt, npre, nsamp; version="2.2.0",
    channel=1, num_rows=32, num_cols=8)

Create a new file, write an LJH Header to it, and return an `LJHFile` ready for
writing with `write`.  `dt` in seconds. `npre` is the number of presamples.
`nsamp` is the number of samples per record. Versions "2.2.0", "2.1.0", and "2.0.0" are supported.
"""
function create(filename::AbstractString, dt, npre, nsamp; version="2.2.0", channel=1, num_rows=32, num_cols=8)
    f = open(filename,"w+")
    writeljhheader(f, dt, npre, nsamp; version=version, channel=channel, num_rows=num_rows, num_cols=num_cols)
    LJHFile(filename,seekstart(f))
end

"""
    writeljhheader(filename::AbstractString, dt, npre, nsamp; version="2.2.0",channel=1, num_rows=32, num_cols=8)
    writeljhheader(io::IO, dt, npre, nsamp; version="2.2.0",channel=1, num_rows=32, num_cols=8)

Write a header for an LJH file. `dt` in seconds. `npre` is the number of presamples.
`nsamp` is the number of samples per record. Versions "2.2.0", "2.1.0", and "2.0.0" are supported.
`create_ljh` is easier to use.
"""
function writeljhheader(filename::AbstractString, dt, npre, nsamp; version="2.2.0", channel=1, num_rows=32, num_cols=8)
    open(filename, "w") do f
    writeljhheader(f, dt, npre, nsamp; version=version)
    end #do
end

# the header here seems absurd, yes
# but it is intended to allow compatilibity with older LJH readers,
# like that in IGOR
function writeljhheader(io::IO, dt, npre, nsamp; version="2.2.0", channel=1, num_rows=32, num_cols=8)
    write(io,
"#LJH Memorial File Format
Save File Format Version: $version
Software Version: LJH file generated by Julia
Software Driver Version: n/a
Date: %(asctime)s GMT
Acquisition Mode: 0
Digitized Word Size in bytes: 2
Location: LANL, presumably
Cryostat: Unknown
Thermometer: Unknown
Temperature (mK): 100.0000
Bridge range: 20000
Magnetic field (mGauss): 100.0000
Detector:
Sample:
Excitation/Source:
Operator: Unknown
SYSTEM DESCRIPTION OF THIS FILE:
USER DESCRIPTION OF THIS FILE:
#End of description
Number of Digitizers: 1
Number of Active Channels: 1
Timestamp offset (s): 1304449182.876200
Digitizer: 1
Description: CS1450-1 1M ver 1.16
Master: Yes
Bits: 16
Effective Bits: 0
Anti-alias low-pass cutoff frequency (Hz): 0.000
Timebase: $dt
Number of samples per point: 1
Number of rows: $num_rows
Number of columns: $num_cols
Presamples: $npre
Total Samples: $nsamp
Trigger (V): 250.000000
Tigger Hysteresis: 0
Trigger Slope: +
Trigger Coupling: DC
Trigger Impedance: 1 MOhm
Trigger Source: CH A
Trigger Mode: 0 Normal
Trigger Time out: 351321
Use discrimination: No
Channel: $channel
Description: A (Voltage)
Range: 0.500000
Offset: -0.000122
Coupling: DC
Impedance: 1 Ohms
Inverted: No
Preamp gain: 1.000000
Discrimination level (%%): 1.000000
#End of Header\n"
    )
flush(io)
end

"    write(ljh::LJHFile{LJH_22},traces::Array{UInt16,2}, rowcounts::Vector{Int64}, times::Vector{Int64})"
function Base.write(ljh::LJHFile{LJH_22},traces::Array{UInt16,2}, rowcounts::Vector{Int64}, times::Vector{Int64})
    for j = 1:length(times)
        write(ljh, traces[:,j], rowcounts[j], times[j])
    end
end
"    write(ljh::LJHFile{LJH_22}, trace::Vector{UInt16}, rowcount::Int64, time::Int64)"
function Base.write(ljh::LJHFile{LJH_22}, trace::Vector{UInt16}, rowcount::Int64, timestamp_usec::Int64)
    write(ljh.io, rowcount, timestamp_usec, trace)
end
"    write(ljh::LJHFile{LJH_22}, record::LJHRecord)"
function Base.write(ljh::LJHFile{LJH_22}, record::LJHRecord)
  write(ljh, record.data, record.rowcount, record.timestamp_usec)
end

"    write(ljh::LJHFile,traces::Array{UInt16,2}, rowcounts::Vector{Int64})"
function Base.write(ljh::LJHFile,traces::Array{UInt16,2}, rowcounts::Vector{Int64})
    for j = 1:length(rowcounts)
        write(ljh, traces[:,j], rowcounts[j])
    end
end
"    write(ljh::LJHFile{LJH_21}, trace::Vector{UInt16}, rowcount::Int64)"
function Base.write(ljh::LJHFile{LJH_21}, trace::Vector{UInt16}, rowcount::Int64)
  lsync_us = 1e6*frametime(ljh)/num_rows(ljh)
  timestamp_us = round(Int, rowcount*lsync_us)
  timestamp_ms = Int32(div(timestamp_us, 1000))
  subms_part = round(UInt8, mod(div(timestamp_us,4), 250))
  z = Int8(0)
  write(ljh.io, subms_part)
  write(ljh.io, z) # Required to be zero.
  write(ljh.io, timestamp_ms)
  write(ljh.io, trace)
end
"    write(ljh::LJHFile{LJH_20}, trace::Vector{UInt16}, rowcount::Int64)"
function Base.write(ljh::LJHFile{LJH_20}, trace::Vector{UInt16}, rowcount::Int64)
  lsync_us = 1e6*frametime(ljh)/num_rows(ljh)
  timestamp_us = round(Int, rowcount*lsync_us)
  timestamp_ms = Int32(div(timestamp_us, 1000))
  z = Int8(0)
  write(ljh.io, z)
  write(ljh.io, z) # Required to be zero.
  write(ljh.io, timestamp_ms)
  write(ljh.io, trace)
end
"    Base.write(ljh::LJHFile, record::LJHRecord)"
function Base.write(ljh::LJHFile, record::LJHRecord)
  write(ljh, record.data, record.rowcount)
end

#
include("ljh3.jl")
end #module
