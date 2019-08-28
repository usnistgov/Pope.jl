using Pope, HDF5
using Pope.LJH
using Test
using ReferenceMicrocalFiles

@testset "BufferedHDF5Dataset2D" begin
    for name in ["ds","1/ds"]
        h5 = h5open(tempname(),"w")
        chunksize = 100
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
    FrameTime, PretrigNSamples, NRow, row = 9.6e-6, 100, 30, 1
    # rowcount of LJH2 files = framecount*NRow+row, framecount=frame1index
    r = LJH.LJHRecord{FrameTime, PretrigNSamples, NRow}(1:1000,10*NRow+row,20)
    r3 = LJH.LJH3Record{FrameTime}(1:1000,PretrigNSamples,10,20)
    projectors = rand(6,1000)
    analyzer = Pope.BasisAnalyzer(projectors, projectors')
    dp = analyzer(r)
    dp3 = analyzer(r3)
    @test Pope.nbases(analyzer) == 6
    @test Pope.nsamples(analyzer) == 1000
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
    fetch(b)
    @test read(h5["1/reduced"]) == reshape(1:6,(6,1))
    @test read(h5["1/residual_std"]) == [dataproduct.residual_std]
    @test read(h5["1/frame1index"]) == [dataproduct.frame1index]
    @test read(h5["1/timestamp_usec"]) == [dataproduct.timestamp_usec]
    @test read(h5["1/first_rising_sample"]) == [dataproduct.first_rising_sample]
    @test read(h5["1/nsamples"]) == [dataproduct.nsamples]
    close(h5)
    rm(h5.filename)
end
