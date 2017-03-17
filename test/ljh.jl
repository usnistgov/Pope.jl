using Base.Test
using Pope: LJH

# Write file 1 as an LJH 2.1 file and files 2 as LJH 2.2 with identical data.
name21, f1 = mktemp()
name22, f2 = mktemp()

dt = 9.6e-6
npre = 200
nsamp = 1000
nrow = 30

LJH.writeljhheader(f1, dt, npre, nsamp; version="2.1.0", number_of_rows=nrow)
LJH.writeljhheader(f2, dt, npre, nsamp; version="2.2.0", number_of_rows=nrow)

rowcount = collect(5000:1000:10000)
timestamps = [Int64(round(r*(dt/30)*1e6)) for r in rowcount]
N = length(rowcount)

data = rand(UInt16, nsamp, N)
data[1,:] = 0xffff

ljh_f1 = LJH.LJHFile(name21,seekstart(f1))
ljh_f2 = LJH.LJHFile(name22,seekstart(f2))

write(ljh_f1, data, rowcount)
write(ljh_f2, data, rowcount, timestamps)

close(f1)
close(f2)
# Now check that the data are readable
ljh21 = LJHGroup(name21)
ljh22 = LJHGroup(name22)

@testset "ljh" begin

# Test that the header info is correct
for ljh in (ljh21, ljh22)
    @test record_nsamples(ljh) == nsamp
    @test pretrig_nsamples(ljh) == npre
    @test frametime(ljh) == dt
    @test length(ljh) == N

    # Test indexed access
    ranges = (1:N, N:-1:1, 1:3:N, N:-2:1)
    for r in ranges
        for i = r
            record = ljh[i]
            @test record.data==data[:,i]
            @test record.timestamp_usec==timestamps[i]
        end
    end
    row(ljh)
    column(ljh)
    num_rows(ljh)
    num_columns(ljh)

    # test slices
    for (r1,r2) in zip(collect(ljh[2:4]), collect(ljh)[2:4])
        @test r1.data==r2.data
    end
end

# Now a group corresponding to 3 files (actually, same one 3 times)
grp = LJHGroup([name22, name21, name22])
for j=1:3N
    record = grp[j]
    d,r,t = record.data, record.rowcount, record.timestamp_usec
    i = mod(j-1, N)+1
    @test d==data[:,i]
    @test t==timestamps[i]
end


for (r1,r2) in zip(collect(grp[3:10]), collect(grp)[3:10])
    @test r1.data == r2.data
    @test r1.rowcount == r2.rowcount
    @test r1.timestamp_usec == r2.timestamp_usec
end
@test lengths(grp) == [N,N,N]

grp.ljhfiles[1].record_nsamples=0
@test_throws AssertionError record_nsamples(grp)

data_r, rowcount_r, timestamp_usec_r = get_data_rowcount_timestamp(ljh22)
for i = 1:N
  @assert data[:,1]==data_r[1]
end
@assert rowcount_r==rowcount
@assert timestamp_usec_r == timestamps

# test tryread
ljh = LJH.LJHFile(name22)
LJH.seekto(ljh,1)
data = get(LJH.tryread(ljh))
data2 = ljh[1]
while !isnull(LJH.tryread(ljh)) end
close(ljh)
@test data==data2
end #testset ljh
