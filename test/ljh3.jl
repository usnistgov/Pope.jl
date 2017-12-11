using Pope: LJH
using DataStructures
using Base.Test

@testset "ljh3" begin

header_extra = OrderedDict(["a"=>"b","c"=>"d","e"=>Dict("ea"=>"eb")])
fname = tempname()
fw = LJH.create3(fname, 9.6e-6, header_extra)

traces = [rand(UInt16,rand(1:1000)) for i=1:10000];
first_rising_samples = [rand(1:length(trace)) for trace in traces];
samplecounts = 1:length(traces);
timestamp_usecs = samplecounts.*1000;

for i = 1:length(traces)
    write(fw, traces[i],first_rising_samples[i],
     samplecounts[i], timestamp_usecs[i])
end
@test fw[1].data == traces[1]
@test fw[77].data == traces[77]
close(fw)

f = LJH3File(fname)
f2 = LJH3File(fname)
records = [record for record in f];
@test fw.index == f.index
@test traces == [record.data for record in records]
@test first_rising_samples == [record.first_rising_sample for record in records]
@test collect(samplecounts) == [record.samplecount for record in records]
@test timestamp_usecs == [record.timestamp_usec for record in records]
@test records == collect(f)
@test f[1].data == traces[1]
@test f[77].data == traces[77]
@test all(f[key]==f.header[key] for key in keys(f))
@test all(f[key]==f.header[key] for key in keys(header_extra))
@test length(f2) == length(traces) # test that length works before collect is called on f2
@test f2.index == f.index
LJH.seekto(f,length(traces)-1)
@test get(LJH.tryread(f))==records[end-1]
@test get(LJH.tryread(f))==records[end]
@test isnull(LJH.tryread(f))
close(f)
close(f2)
rm(fname)
end



# using BenchmarkTools
# @benchmark read(seekstart(f.io)) setup=(f=LJH3File(fname)) teardown=close(f)
# @benchmark collect(f) setup=(f=LJH3File(fname)) teardown=close(f)
