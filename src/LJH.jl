module LJH

export LJHGroup, channel, record_nsamples, pretrig_nsamples, frametime, filenames, lengths, column, row, num_columns, num_rows, get_data_rowcount_timestamp

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

mutable struct LJHFile{VersionInt, T<:IO}
    filename             ::String   # filename
    io               ::IO         # IO to read from LJH file
    headerdict       ::Dict             # LJH file header data
    datastartpos     ::Int
    frametime        ::Float64          # sample spacing (microseconds)
    pretrig_nsamples ::Int64            # nPresample
    record_nsamples  ::Int64            # number of sample per record
    channum          ::Int16            # channel number
    column           ::Int16            # column number
    row              ::Int16            # row number
    num_columns      ::Int16            # number of rows
    num_rows         ::Int16            # number of columns
end
struct LJHRecord
    data::Vector{UInt16}
    rowcount::Int64
    timestamp_usec::Int64
end
data(r::LJHRecord) = r.data
rowcount(r::LJHRecord) = r.rowcount
timestamp_usec(r::LJHRecord) = r.timestamp_usec
import Base: ==
==(a::LJHRecord, b::LJHRecord) = a.data==b.data && a.rowcount == b.rowcount && a.timestamp_usec == b.timestamp_usec

@enum LJHVERSION LJH_21 LJH_22
VERSIONS = Dict(v"2.1.0"=>LJH_21, v"2.2.0"=>LJH_22)

LJHFile(fname::String) = LJHFile(fname,open(fname,"r"))
function LJHFile(fname::String,io::IO)
    headerdict = ljh_get_header_dict(seekstart(io))
    datastartpos = position(io)
    # ioend = position(seekend(io))
    ioend = stat(io).size
    # seek(io,datastartpos)
    version = VersionNumber(headerdict["Save File Format Version"])
    version in keys(VERSIONS) || error("$fname has version $version, which is not in VERSIONS $VERSIONS")
    versionint = VERSIONS[version]
    record_nsamples = parse(Int,headerdict["Total Samples"])
    num_rows = parse(Int16, get(headerdict,"Number of rows","0"))
    num_columns = parse(Int16, get(headerdict,"Number of columns","0"))
    LJHFile{versionint, typeof(io)}(
        fname, # filename
        io, # IO
        headerdict, #headerdict
        datastartpos, # datastartpos
        parse(Float64,headerdict["Timebase"]), # frametime
        parse(Int16,headerdict["Presamples"]), # pretrig_nsamples
        parse(Int16,headerdict["Total Samples"]), # record_nsamples
        round(Int16,parse(Float64,headerdict["Channel"])), # channel number
        parse(Int16,get(headerdict,"Column number (from 0-$(num_columns-1) inclusive)","0")),   #column, defaults to zero if not in file
        parse(Int16,get(headerdict,"Row number (from 0-$(num_rows-1) inclusive)","0")), #row, defaults to zero if not in file
        num_columns, # num_columns
        num_rows) # num_rows
end
LJHFile(f::LJHFile) = f

"record_nbytes(f::LJHFile)
    Return number of bytes per record in LJH file, based on version number"
record_nbytes(f::LJHFile{LJH_21,T}) where T = 6+2*f.record_nsamples
record_nbytes(f::LJHFile{LJH_22,T}) where T = 16+2*f.record_nsamples

"    ljh_number_of_records(f::LJHFile)
Return the number of complete records currently available to read from `f`."
function ljh_number_of_records(f::LJHFile)
    # oldpos = position(f.io)
    # endpos = position(seekend(f.io))
    nbytes = stat(f.io).size-f.datastartpos
    # seek(f.io,oldpos)
    number_of_records = div(nbytes, record_nbytes(f))
end

Base.divrem(f::LJHFile) = divrem(stat(f.filename).size-f.datastartpos,record_nbytes(f))


# support for ljhfile[1:7] syntax
seekto(f::LJHFile, i::Int) = seek(f.io,f.datastartpos+(i-1)*record_nbytes(f))
Base.getindex(f::LJHFile,indexes::AbstractVector)=LJHGroupSlice(LJHGroup(f), indexes)
function Base.getindex(f::LJHFile,index::Int)
    seekto(f, index)
    pop!(f)
end
function Base.pop!{T}(f::LJHFile{LJH_21,T})
    rowcount, timestamp_usec =  record_row_count_v21(read(f.io, UInt8, 6), f.num_rows, f.row, f.frametime)
    data = read(f.io, UInt16, f.record_nsamples)
    LJHRecord(data, rowcount, timestamp_usec)
end
function Base.pop!{T}(f::LJHFile{LJH_22,T})
    rowcount = read(f.io, Int64)
    timestamp_usec = read(f.io, Int64)
    data = read(f.io, UInt16, f.record_nsamples)
    LJHRecord(data, rowcount, timestamp_usec)
end
Base.size(f::LJHFile) = (ljh_number_of_records(f),)
Base.length(f::LJHFile) = ljh_number_of_records(f)
Base.endof(f::LJHFile) = ljh_number_of_records(f)
# access as iterator
Base.start(f::LJHFile) = (seekto(f,1);1)
Base.next(f::LJHFile,j) = pop!(f),j+1
Base.done(f::LJHFile,j) = j==length(f)+1
filename(f::LJHFile) = f.filename
record_nsamples(f::LJHFile) = f.record_nsamples
pretrig_nsamples(f::LJHFile) = f.pretrig_nsamples
channel(f::LJHFile) = f.channum
row(f::LJHFile) = f.row
column(f::LJHFile) = f.column
frametime(f::LJHFile) = f.frametime
function Base.show(io::IO, g::LJHFile)
    print(io, "LJHFile $(filename(g))\n")
    print(io, "$(length(g)) records\n")
    print(io, "record_nsamlpes $(record_nsamples(g)), pretrig_nsamples $(pretrig_nsamples(g)).\n")
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
function tryread{T}(f::LJHFile{LJH_22,T})
  d = read(f.io,record_nbytes(f))
  if length(d) == record_nbytes(f)
    rowcount = reinterpret(Int,d[1:8])[1]
    timestamp_usec = reinterpret(Int,d[9:16])[1]
    data = reinterpret(UInt16,d[17:record_nbytes(f)])
    return Nullable(LJHRecord(data, rowcount, timestamp_usec))
  else
    seek(f.io, position(f.io)-length(d)) # go back to the start of the record
    return Nullable{LJHRecord}()
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

function tryread{T}(f::LJHFile{LJH_21,T})
  d1 = read(f.io, 6)
  length(d1) == 0  && return Nullable{LJHRecord}()
  rowcount, timestamp_usec =  record_row_count_v21(d1, f.num_rows, f.row, f.frametime)
  data = read(f.io, UInt16, f.record_nsamples)
  return Nullable(LJHRecord(data, rowcount, timestamp_usec))
end
watch_file(f::LJHFile, timeout_s::Real) = watch_file(f.filename, timeout_s)

"""Used only for reading LJH version 2.1.0 files. This parses the ugly
"encoded" version of the frame counter, which is converted into an
approximate time, rounded to 4 microseconds, and divided into the integer
and fractional parts of the millisecond. The latter are stored in bytes
3-6, and the former is in byte 1. Ignore byte 2 (it has some need to be
0 for backward compatibility). Ugly! That's why LJH 2.2.0 does something
totally different.
"""
function record_row_count_v21(header::Vector{UInt8}, num_rows::Integer, row::Integer, frame_time::Float64)
    frac = Int64(header[1])
    ms = UInt64(header[3]) |
         (UInt64(header[4])<<8) |
         (UInt64(header[5])<<16) |
         (UInt64(header[6])<<24)
    count_4usec = Int64(ms*250+frac)
    ns_per_frame = round(Int64,frame_time*1e9)
    ns_per_4usec = Int64(4000)
    count_nsec = count_4usec*ns_per_4usec
    count_frame = cld(count_nsec,ns_per_frame)
    rowcount = count_frame*num_rows+row
    return rowcount, 4*count_4usec
end

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
pretrig_nsamples(g::LJHGroup) = (assert(length(fieldvalue(g, :pretrig_nsamples))==1);g.ljhfiles[1].pretrig_nsamples)
frametime(g::LJHGroup) = (assert(length(fieldvalue(g, :frametime))==1);g.ljhfiles[1].frametime)
column(g::LJHGroup) = (assert(length(fieldvalue(g, :column))==1);g.ljhfiles[1].column)
row(g::LJHGroup) = (assert(length(fieldvalue(g, :row))==1);g.ljhfiles[1].row)
num_columns(g::LJHGroup) = (assert(length(fieldvalue(g, :num_columns))==1);g.ljhfiles[1].num_columns)
num_rows(g::LJHGroup) = (assert(length(fieldvalue(g, :num_rows))==1);g.ljhfiles[1].num_rows)
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
LJHGroupSlice{T<:AbstractArray}(ljhfile::LJHGroup, slice::T) = LJHGroupSlice{T}(ljhfile, slice)
function Base.start{T<:UnitRange}(g::LJHGroupSlice{T})
    for f in g.g.ljhfiles seekto(f,1) end
    isempty(g.slice) && return (2,2,1,1) # ensure done condition is immediatley met on empty range
    filenum, recordnum = filenum_recordnum(g.g, first(g.slice))
    donefilenum, donerecordnum = filenum_recordnum(g.g, last(g.slice))
    seekto(g.g.ljhfiles[filenum], recordnum)
    (filenum, recordnum, donefilenum, donerecordnum)
end
function Base.next{T<:UnitRange}(g::LJHGroupSlice{T}, state)
    filenum, recordnum, donefilenum, donerecordnum = state
    ljhrecord = pop!(g.g.ljhfiles[filenum])
    recordnum+=1
    recordnum > g.g.lengths[filenum] && (recordnum-=g.g.lengths[filenum];filenum+=1)
    ljhrecord, (filenum, recordnum, donefilenum, donerecordnum)
end
function Base.done{T<:UnitRange}(g::LJHGroupSlice{T}, state)
    filenum, recordnum, donefilenum, donerecordnum = state
    filenum>donefilenum || filenum==donefilenum && recordnum>donerecordnum
end

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

"""
    create(filename::AbstractString, dt, npre, nsamp; version="2.2.0",
    channel=1, number_of_rows=32, number_of_columns=8)

Create a new file, write an LJH Header to it, and return an `LJHFile` ready for
writing with `write`.  `dt` in seconds. `npre` is the number of presamples.
`nsamp` is the number of samples per record. Versions "2.2.0" and "2.1.0" are supported.
"""
function create(filename::AbstractString, dt, npre, nsamp; version="2.2.0", channel=1, number_of_rows=32, number_of_columns=8)
    f = open(filename,"w+")
    writeljhheader(f, dt, npre, nsamp; version=version, channel=channel, number_of_rows=number_of_rows, number_of_columns=number_of_columns)
    LJHFile(filename,seekstart(f))
end

"""
    writeljhheader(filename::AbstractString, dt, npre, nsamp; version="2.2.0",channel=1, number_of_rows=32, number_of_columns=8)
    writeljhheader(io::IO, dt, npre, nsamp; version="2.2.0",channel=1, number_of_rows=32, number_of_columns=8)

Write a header for an LJH file. `dt` in seconds. `npre` is the number of presamples.
`nsamp` is the number of samples per record. Versions "2.2.0" and "2.1.0" are supported.
`create_ljh` is easier to use.
"""
function writeljhheader(filename::AbstractString, dt, npre, nsamp; version="2.2.0", channel=1, number_of_rows=32, number_of_columns=8)
    open(filename, "w") do f
    writeljhheader(f, dt, npre, nsamp; version=version)
    end #do
end

# the header here seems absurd, yes
# but it is intended to allow compatilibity with older LJH readers,
# like that in IGOR
function writeljhheader(io::IO, dt, npre, nsamp; version="2.2.0", channel=1, number_of_rows=32, number_of_columns=8)
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
Number of rows: $number_of_rows
Number of columns: $number_of_columns
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

"    write{T}(ljh::LJHFile{LJH_22,T},traces::Array{UInt16,2}, rowcounts::Vector{Int64}, times::Vector{Int64})"
function Base.write{T}(ljh::LJHFile{LJH_22,T},traces::Array{UInt16,2}, rowcounts::Vector{Int64}, times::Vector{Int64})
    for j = 1:length(times)
        write(ljh, traces[:,j], rowcounts[j], times[j])
    end
end
"    write{T}(ljh::LJHFile{LJH_22,T}, trace::Vector{UInt16}, rowcount::Int64, time::Int64)"
function Base.write{T}(ljh::LJHFile{LJH_22,T}, trace::Vector{UInt16}, rowcount::Int64, timestamp_usec::Int64)
    write(ljh.io, rowcount, timestamp_usec, trace)
end
"    write{T}(ljh::LJHFile{LJH_22,T}, record::LJHRecord)"
function Base.write{T}(ljh::LJHFile{LJH_22,T}, record::LJHRecord)
  write(ljh, record.data, record.rowcount, record.timestamp_usec)
end

"    write{T}(ljh::LJHFile{LJH_21,T},traces::Array{UInt16,2}, rowcounts::Vector{Int64})"
function Base.write{T}(ljh::LJHFile{LJH_21,T},traces::Array{UInt16,2}, rowcounts::Vector{Int64})
    for j = 1:length(rowcounts)
        write(ljh, traces[:,j], rowcounts[j])
    end
end
"    write{T}(ljh::LJHFile{LJH_21,T}, trace::Vector{UInt16}, rowcount::Int64)"
function Base.write{T}(ljh::LJHFile{LJH_21,T}, trace::Vector{UInt16}, rowcount::Int64)
  lsync_us = 1e6*ljh.frametime/ljh.num_rows
  timestamp_us = round(Int, rowcount*lsync_us)
  timestamp_ms = Int32(div(timestamp_us, 1000))
  subms_part = round(UInt8, mod(div(timestamp_us,4), 250))
  channum = Int8(ljh.channum)
  write(ljh.io, subms_part)
  write(ljh.io, channum)
  write(ljh.io, timestamp_ms)
  write(ljh.io, trace)
end
"    Base.write{T}(ljh::LJHFile{LJH_21,T}, record::LJHRecord)"
function Base.write{T}(ljh::LJHFile{LJH_21,T}, record::LJHRecord)
  write(ljh, record.data, record.rowcount)
end

#

end #module
