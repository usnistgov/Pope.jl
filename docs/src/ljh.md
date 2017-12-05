# LJH
LJH is a module for reading and writing LJH files. It supports versions 2.1 and
2.2 of LJH, and provides a way to handle multiple LJH files.

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

## Autodocs LJH
```@autodocs
Modules = [LJH]
Order   = [:type, :function]
```