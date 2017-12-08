using Pope: LJH
using DataStructures
using Base.Test

header_extra = OrderedDict(["a"=>"b","c"=>"d","e"=>Dict("ea"=>"eb")])
fname = tempname()
f = LJH.create3(fname, 9.6e-6, header_extra)

traces = [rand(UInt16,rand(1:1000)) for i=1:100]
first_rising_samples = [rand(1:length(trace)) for trace in traces]
rowcounts = 1:length(traces)
timestamp_usecs = rowcounts.*1000

for i = 1:length(traces)
    Base.write(f, traces[i],first_rising_samples[i],
     rowcounts[i], timestamp_usecs[i])
end
close(f)

f = LJH.LJH3File(fname)
f2 = LJH.LJH3File(fname)
records = [record for record in f]
@testset "ljh3" begin
    @test traces == [record.data for record in records]
    @test first_rising_samples == [record.first_rising_sample for record in records]
    @test collect(rowcounts) == [record.rowcount for record in records]
    @test timestamp_usecs == [record.timestamp_usec for record in records]
    @test f[1].data == traces[1]
    @test f[77].data == traces[77]
    @test all(f[key]==f.header[key] for key in keys(f))
    @test all(f[key]==f.header[key] for key in keys(header_extra))
    @test length(f2) == length(traces) # test that length works before collect is called on f2
    @test f2.index == f.index
end
close(f)
close(f2)
rm(fname)
