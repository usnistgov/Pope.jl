# LJH
LJH is a module for reading and writing LJH files. It supports versions 2.1 and
2.2 of LJH, and provides a way to handle multiple LJH files. It is a submodule of Pope so you will want to `using Pope.LJH` or `using Pope: LJH`.

```@contents
Depth = 2
```

```@meta
DocTestSetup = quote using Pope.LJH end
```
## Writing LJH Files
```jldoctest ljh
julia> dt = 9.6e-6; npre = 200; nsamp = 1000; nrow = 30; rowcount = 1; timestamp=2;

julia> ljh = LJH.create("ljh.ljh", dt, npre, nsamp; version="2.2.0", number_of_rows=nrow)
LJHFile ljh.ljh
0 records
record_nsamlpes 1000, pretrig_nsamples 200.
Channel 1, row 0, column 0, frametime 9.6e-6 s.


julia> write(ljh, Vector{UInt16}(1:nsamp), rowcount, timestamp)
2016

julia> write(ljh, Vector{UInt16}(1:nsamp), rowcount, timestamp)
2016

julia> close(ljh)
```

## Reading LJH Files
```jldoctest ljh
julia> ljhr = LJH.LJHFile(LJH.filename(ljh))
LJHFile ljh.ljh
2 records
record_nsamlpes 1000, pretrig_nsamples 200.
Channel 1, row 0, column 0, frametime 9.6e-6 s.


julia> record = ljhr[1];

julia> LJH.data(record)' # transpose for less verbose output
1×1000 RowVector{UInt16,Array{UInt16,1}}:
 0x0001  0x0002  0x0003  0x0004  0x0005  …  0x03e5  0x03e6  0x03e7  0x03e8

julia> LJH.rowcount(record)
1

julia> LJH.timestamp_usec(record)
2

julia> records = collect(ljhr)
2-element Array{Any,1}:
 Pope.LJH.LJHRecord(UInt16[0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0008, 0x0009, 0x000a  …  0x03df, 0x03e0, 0x03e1, 0x03e2, 0x03e3, 0x03e4, 0x03e5, 0x03e6, 0x03e7, 0x03e8], 1, 2)
 Pope.LJH.LJHRecord(UInt16[0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0008, 0x0009, 0x000a  …  0x03df, 0x03e0, 0x03e1, 0x03e2, 0x03e3, 0x03e4, 0x03e5, 0x03e6, 0x03e7, 0x03e8], 1, 2)

julia> LJH.rowcount.(records)
2-element Array{Int64,1}:
 1
 1

julia> records2 = collect(ljhr[1:1])
1-element Array{Any,1}:
 Pope.LJH.LJHRecord(UInt16[0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0008, 0x0009, 0x000a  …  0x03df, 0x03e0, 0x03e1, 0x03e2, 0x03e3, 0x03e4, 0x03e5, 0x03e6, 0x03e7, 0x03e8], 1, 2)

julia> data, rowcount, timestamp_usec = LJH.get_data_rowcount_timestamp(ljhr)
(UInt16[0x0001 0x0001; 0x0002 0x0002; … ; 0x03e7 0x03e7; 0x03e8 0x03e8], [1, 1], [2, 2])

julia> close(ljhr)

```

### Reading LJH files when data may or may not be available
```jldoctest ljh
julia> ljhr = LJH.LJHFile(LJH.filename(ljh));

julia> LJH.tryread(ljhr)
Nullable{Pope.LJH.LJHRecord}(Pope.LJH.LJHRecord(UInt16[0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0008, 0x0009, 0x000a  …  0x03df, 0x03e0, 0x03e1, 0x03e2, 0x03e3, 0x03e4, 0x03e5, 0x03e6, 0x03e7, 0x03e8], 1, 2))

julia> LJH.tryread(ljhr)
Nullable{Pope.LJH.LJHRecord}(Pope.LJH.LJHRecord(UInt16[0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0008, 0x0009, 0x000a  …  0x03df, 0x03e0, 0x03e1, 0x03e2, 0x03e3, 0x03e4, 0x03e5, 0x03e6, 0x03e7, 0x03e8], 1, 2))

julia> LJH.tryread(ljhr)
Nullable{Pope.LJH.LJHRecord}()

julia> close(ljhr)

```

### Reading many LJH files simultaneously
```jldoctest ljh
julia> names = [c*".ljh" for c in ["a","b","c"]]
3-element Array{String,1}:
 "a.ljh"
 "b.ljh"
 "c.ljh"

julia> for name in names
                         ljh = LJH.create(name, dt, npre, nsamp; version="2.2.0", number_of_rows=nrow)
                         write(ljh, ones(UInt16,nsamp,5), collect(1:5), collect(1:5))
                         close(ljh)
                     end

julia> g = LJHGroup(names)
LJHGroup with 3 files, 15 records, split as [5, 5, 5],record_nsampes 1000,
pretrig_nsamples 200.channel 1, row 0, column 0, frametime 9.6e-6 s.
First filename a.ljh

julia> g[7]
Pope.LJH.LJHRecord(UInt16[0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001  …  0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001], 2, 2)

julia> g[2:12]
Pope.LJH.LJHGroupSlice{UnitRange{Int64}}(LJHGroup with 3 files, 15 records, split as [5, 5, 5],record_nsampes 1000,
pretrig_nsamples 200.channel 1, row 0, column 0, frametime 9.6e-6 s.
First filename a.ljh, 2:12)

julia> collect(g[7:8])
2-element Array{Any,1}:
 Pope.LJH.LJHRecord(UInt16[0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001  …  0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001], 2, 2)
 Pope.LJH.LJHRecord(UInt16[0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001  …  0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001, 0x0001], 3, 3)
```
```@meta
DocTestSetup = nothing
```

## LJH Filename Handling
There are a set of utility functions for handling LJH filenames. These are some of the most useful functions. These function can accept either a fully qualified ljh filename like `ljhutil_doctest/ljhutil_doctest_chan1.ljh` or a directory as long as it exists, and contains ljh files whose "base" name is the same as the directory name. So passing `ljhutil_doctest` should have the same result as passing that fully qualified name.

The following examples work if a directory `ljhutil_doctest` exists, and contains ljh files.

```@meta
DocTestSetup = quote
using Pope.LJH
dir = "ljhutil_doctest"
isdir(dir) || mkdir(dir)
fnames = LJH.fnames(joinpath(dir,"ljhutil_doctest"),1:2:480)
for fname in fnames
    touch(fname)
end
end
```

```jldoctest
julia> # the second argument is `maxchannels` to limit output length
       ljhdict = LJH.allchannels("ljhutil_doctest/ljhutil_doctest_chan1.ljh",4)
DataStructures.OrderedDict{Int64,String} with 4 entries:
  1 => "ljhutil_doctest/ljhutil_doctest_chan1.ljh"
  3 => "ljhutil_doctest/ljhutil_doctest_chan3.ljh"
  5 => "ljhutil_doctest/ljhutil_doctest_chan5.ljh"
  7 => "ljhutil_doctest/ljhutil_doctest_chan7.ljh"

julia> dir,base,ext = LJH.dir_base_ext(first(values(ljhdict)))
("ljhutil_doctest", "ljhutil_doctest", ".ljh")

julia> LJH.pope_output_hdf5_name_from_ljh(first(values(ljhdict)))
"ljhutil_doctest_pope.hdf5"

julia> channels,fnames = collect(keys(ljhdict)), collect(values(ljhdict))
([1, 3, 5, 7], String["ljhutil_doctest/ljhutil_doctest_chan1.ljh", "ljhutil_doctest/ljhutil_doctest_chan3.ljh", "ljhutil_doctest/ljhutil_doctest_chan5.ljh", "ljhutil_doctest/ljhutil_doctest_chan7.ljh"])
```

```@meta
CurrentModule = LJH
DocTestSetup = nothing
```

```@docs
allchannels
dir_base_ext
pope_output_hdf5_name_from_ljh
```

## Matter Sentinel File Handling
```@docs
matter_writing_status
write_sentinel_file
change_writing_status
```

## LJH3

LJH3 is a new version of LJH intended to allow the use of variable length records for analyses such as multi-pulse fitting or single pulse fitting. LJH3 files have a JSON header containing at least 3 keys: "sampleperiod", "File Format"="LJH3", and "File Format Version". It should contain additional keys with information about the readout, but these are not currently required. The JSON is followed by a single newline "\n".

Immediatley following the header, records are written as flat binary data. Each record consists of a `Int32` record length, a `Int32` offset into the record pointing to the first rising sample as determined by the trigger algorithm, a `Int64` frame1index of the first sample in the record, and an `Int64` posix timestamp in units of microseconds since the epoch for the first sample in the record. The frame1index is provided by the readout system, and may have arbitrary offset, such that comparisons across different LJH3 files from the same readout system are not meaningful.

## LJH Records and LJH3 Records API
Both `LJHRecord` from version 2 files, and `LJH3Record` from version 3 files have a shared API. The API consists of the functions `frameperiod`, `frame1index`, `first_rising_sample`, `data`, and `timestamp_usec`. 


```@docs
LJH3File
LJH3Record
create3
write(ljh::LJH3File, trace::Vector{UInt16},first_rising_sample, samplecount::Int64, timestamp_usec::Int64)
```

## Autodocs LJH
```@autodocs
Modules = [LJH]
Order   = [:type, :function]
```
