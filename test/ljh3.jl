using Pope.LJH
using DataStructures
using Nullables
using Test

@testset "ljh3" begin

header_extra = OrderedDict(["a"=>"b","c"=>"d","e"=>Dict("ea"=>"eb")])
fname = tempname()
fw = LJH.create3(fname, 9.6e-6, header_extra)

traces = [rand(UInt16,rand(1:1000)) for i=1:10000];
first_rising_samples = [rand(1:length(trace)) for trace in traces];
frame1indexs = 1:length(traces);
timestamp_usecs = frame1indexs.*1000;

for i = 1:length(traces)
    write(fw, traces[i],first_rising_samples[i],
     frame1indexs[i], timestamp_usecs[i])
end
@test fw[1].data == traces[1]
@test fw[77].data == traces[77]
close(fw)

f = LJH3File(fname)
f2 = ljhopen(fname)
records = [record for record in f];
@test fw.index == f.index
@test traces == [record.data for record in records]
@test first_rising_samples == [record.first_rising_sample for record in records]
@test collect(frame1indexs) == [record.frame1index for record in records]
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
@test LJH.filename(f) == LJH.filename(fw) == fname
close(f)
close(f2)
rm(fname)
end

@testset "LJH3Record and LJHRecord joint API" begin
    FrameTime, PretrigNSamples, NRow, row = 9.6e-6, 100, 30, 1
    # rowcount of LJH2 files = framecount*NRow+row, framecount=frame1index
    r = LJH.LJHRecord{FrameTime, PretrigNSamples, NRow}(1:1000,10*NRow+row,20)
    r3 = LJH.LJH3Record{FrameTime}(1:1000,PretrigNSamples,10,20)
    @test LJH.data(r) == LJH.data(r3)
    @test LJH.frameperiod(r) == LJH.frameperiod(r3)
    @test LJH.first_rising_sample(r) == LJH.first_rising_sample(r3)
    @test LJH.frame1index(r) == LJH.frame1index(r3)
    @test LJH.timestamp_usec(r) == LJH.timestamp_usec(r3)
    @test length(r) == length(r3)
end

# using BenchmarkTools
# @benchmark read(seekstart(f.io)) setup=(f=LJH3File(fname)) teardown=close(f) evals=1
# @benchmark collect(f) setup=(f=LJH3File(fname)) teardown=close(f) evals=1
