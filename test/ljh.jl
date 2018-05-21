using Base.Test
using Pope: LJH


dt = 9.6e-6; npre = 200; nsamp = 1000; nrow = 30
rowcounts = collect(5001:1000:10001)
N=length(rowcounts)
timestamps = [Int64(round(r*(dt/nrow)*1e6)) for r in rowcounts]
data = rand(UInt16, nsamp,N)

fname22 = "artifacts/ljh22_chan1.ljh"
ljh22=LJH.create(fname22, dt, npre, nsamp, version="2.2.0", num_rows=nrow)
write(ljh22, data, rowcounts, timestamps)
close(ljh22)

fname21 = "artifacts/ljh21_chan1.ljh"
ljh21=LJH.create(fname21, dt, npre, nsamp, version="2.1.0", num_rows=nrow)
write(ljh21, data, rowcounts)
close(ljh21)

fname20 = "artifacts/ljh20_chan1.ljh"
ljh20=LJH.create(fname20, dt, npre, nsamp, version="2.0.0", num_rows=nrow)
write(ljh20, data, rowcounts)
close(ljh20)

@testset "LJHGroup for single file access" begin
    for ljh in [LJHGroup(fname20), LJHGroup(fname21), LJHGroup(fname22)]
        @test LJH.record_nsamples(ljh) == nsamp
        @test LJH.pretrig_nsamples(ljh) == npre
        @test LJH.frametime(ljh) == dt
        @test LJH.length(ljh) == N

        for i = 1:length(ljh)
            record = ljh[i]
            @test LJH.data(record)==data[:,i]
            if LJH.filenames(ljh)[1] == fname22
                @test LJH.timestamp_usec(record)==timestamps[i] # LJH22 files calculate a timestamp from the rowcount
                @test LJH.rowcount(record)==rowcounts[i]
            elseif LJH.filenames(ljh)[1] == fname21
                # the rowcount in an LJH21 file is only expected to be accurate to 4 us
                @test abs(LJH.rowcount(record)-rowcounts[i])<=20
            elseif LJH.filenames(ljh)[1] == fname20
                # the rowcount in an LJH20 file is only expected to be accurate to 1 ms
                @test abs(LJH.rowcount(record)-rowcounts[i])<=5000
            end
        end
        LJH.row(ljh)
        LJH.column(ljh)
        LJH.num_rows(ljh)
        LJH.num_columns(ljh)

        # test slices
        for (r1,r2) in zip(collect(ljh[2:4]), collect(ljh)[2:4])
            @test r1.data==r2.data
        end
    end
end

@testset "LJHGroup of 3 files" begin
    grp = LJHGroup([fname22, fname22, fname22])
    for j=1:3N
        record = grp[j]
        d,r,t = LJH.data(record), LJH.rowcount(record), LJH.timestamp_usec(record)
        i = mod(j-1, N)+1
        @test d == data[:,i]
        @test t == timestamps[i]
        @test r == rowcounts[i]
    end
    for (r1,r2) in zip(collect(grp[3:10]), collect(grp)[3:10])
        @test LJH.data(r1) == LJH.data(r2)
        @test LJH.rowcount(r1) == LJH.rowcount(r2)
        @test LJH.timestamp_usec(r1) == LJH.timestamp_usec(r2)
    end
    @test LJH.lengths(grp) == [N,N,N]

    grp.ljhfiles[1].record_nsamples=0
    @test_throws AssertionError LJH.record_nsamples(grp)
end

@testset "LJH single file API" begin
    for ljh in [LJHFile(fname20), LJHFile(fname21), LJHFile(fname22)]
        data_r, rowcount_r, timestamp_usec_r = LJH.get_data_rowcount_timestamp(ljh)
        @test data_r == data
        if LJH.filename(ljh) == fname22
            @test rowcount_r == rowcounts
            @test timestamp_usec_r == timestamps
        elseif LJH.filename(ljh) == fname21
            # the rowcount in an LJH21 file is only expected to be accurate to 4 us
            @test maximum(abs.(rowcount_r-rowcounts)) <= 20
        elseif LJH.filename(ljh) == fname20
            # the rowcount in an LJH20 file is only expected to be accurate to 1 ms
            @test maximum(abs.(rowcount_r-rowcounts)) <= 5000
        end

        LJH.seekto(ljh,N)
        record = get(LJH.tryread(ljh))
        @test isnull(LJH.tryread(ljh))
        @test record == ljh[end]
    end
end

@testset "longrecord" begin
    for ljh in [LJHFile(fname20), LJHFile(fname21), LJHFile(fname22)]
       lr = LJH.read_longrecords(ljh,5000)
       @test length(lr[1])==5000
       @test length(lr)==1
       @test lr[1].data[1:length(ljh[1].data)]==ljh[1].data
    end
end
