using Pope: LJH
using Base.Test

fname = tempname()
f = LJH.create3(fname)
println(f)

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
records = [record for record in f]
@test traces == [record.data for record in records]
@test first_rising_samples == [record.first_rising_sample for record in records]
@test collect(rowcounts) == [record.rowcount for record in records]
@test timestamp_usecs == [record.timestamp_usec for record in records]
@test f[1].data == traces[1]
@test f[77].data == traces[77]
