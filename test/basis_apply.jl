using Pope, HDF5
using Pope.LJH
using Base.Test
using ReferenceMicrocalFiles

@testset "BufferedHDF5Dataset2D" begin
    for name in ["ds","1/ds"]
        h5 = h5open(tempname(),"w")
        const chunksize = 100
        # create an extendible dataset to hold reduced pulses with 6 element basis
        buffer = Pope.BufferedHDF5Dataset2D{Float32}(h5,name,6,1000)
        write(buffer, Vector{Float32}(1:6))
        write(buffer, Vector{Float32}(7:12))
        write(buffer, [Vector{Float32}(13:18), Vector{Float32}(19:24)])
        Pope.write_to_hdf5(buffer)
        @test read(buffer.ds) == reshape(Vector{Float32}(1:24),(6,4))
        close(h5)
        rm(h5.filename)
    end
end

@testset "BasisAnalyzer" begin
    FrameTime, PretrigNSamples = 9.6e-6, 100
    r = LJH.LJHRecord{FrameTime, PretrigNSamples}(1:1000,10,20)
    r3 = LJH.LJH3Record{FrameTime}(1:1000,PretrigNSamples,10,20)
    analyzer = Pope.BasisAnalyzer(rand(6,1000))
    dp = analyzer(r)
    dp3 = analyzer(r3)
    @test dp.reduced == dp3.reduced
    @test dp.residual_std == dp3.residual_std
    @test dp.timestamp_usec == dp3.timestamp_usec == LJH.timestamp_usec(r)
    @test dp.first_rising_sample == dp.first_rising_sample == PretrigNSamples
    @test dp.nsamples == dp3.nsamples == length(r)
end

@testset "BasisBufferedWriter" begin
    h5 = h5open(tempname(),"w")
    g = HDF5.g_create(h5,"1")
    b = Pope.BasisBufferedWriter(g, 6, 1000, 0.001, start=true)
    dataproduct = Pope.BasisDataProduct(collect(1:6),1,2,3,4,5)
    write(b,dataproduct)
    Pope.stop(b)
    wait(b)
    @test read(h5["1/reduced"]) == reshape(1:6,(6,1))
    @test read(h5["1/residual_std"]) == [dataproduct.residual_std]
    @test read(h5["1/frame1index"]) == [dataproduct.frame1index]
    @test read(h5["1/timestamp_usec"]) == [dataproduct.timestamp_usec]
    @test read(h5["1/first_rising_sample"]) == [dataproduct.first_rising_sample]
    @test read(h5["1/nsamples"]) == [dataproduct.nsamples]
    close(h5)
    rm(h5.filename)
end

@testset "LJHFile with BasisAnalyzer" begin
    nbases = 6
    ljh = LJHFile(ReferenceMicrocalFiles.dict["good_mnka_mystery"].filename)
    analyzer = Pope.BasisAnalyzer(rand(nbases,3072));
    h5 = Pope.h5create(tempname());
    g = HDF5.g_create(h5,"$(LJH.channel(ljh))");
    product_writer = Pope.BasisBufferedWriter(g, nbases, 1000, 0.001, start=true);
    ljhreader = Pope.make_reader(LJH.filename(ljh),
        analyzer, product_writer, progress_meter=true);
    readers = Pope.Readers();
    push!(readers, ljhreader)
    schedule(readers)
    Pope.stop(readers)
    wait(readers)
    close(h5)
    h5r = h5open(h5.filename,"r")
    @test (nbases,length(ljh)) == size(h5r["$(LJH.channel(ljh))/reduced"])
    @test all(LJH.record_nsamples(ljh) .== read(h5r["$(LJH.channel(ljh))/nsamples"]))
    @test all( [LJH.rowcount(record) for record in ljh] .== read(h5r["$(LJH.channel(ljh))/frame1index"]) )
    close(ljh)
    close(h5r)
    rm(h5.filename)
end

@testset "BasisAnalyzer with LJH3 file with identical length records" begin
    nbases = 6
    nsamples = 1000
    ljhw = LJH.create3("artifacts/ljh3_chan1.ljh", 9.6e-6)
    for i=1:10 write(ljhw,rand(UInt16,1000),i,i*1000, i*1_000_000) end
    close(ljhw)
    ljh = LJH3File(LJH.filename(ljhw))
    analyzer = Pope.BasisAnalyzer(rand(nbases,nsamples));
    h5 = Pope.h5create(tempname());
    g = HDF5.g_create(h5,"1");
    product_writer = Pope.BasisBufferedWriter(g, nbases, 1000, 0.001, start=true);
    ljhreader = Pope.make_reader(LJH.filename(ljh),
        analyzer, product_writer, progress_meter=true);
    readers = Pope.Readers();
    push!(readers, ljhreader)
    schedule(readers)
    sleep(1)
    Pope.stop(readers)
    wait(readers)
    close(h5)
    h5r = h5open(h5.filename,"r")
    @test read(h5r["1/nsamples"]) == length.(collect(ljh))
    @test read(h5r["1/frame1index"]) == LJH.frame1index.(collect(ljh))
    @test length(read(h5r["1/residual_std"])) == length(ljh)
    close(h5r)
    rm(h5r.filename)
end
