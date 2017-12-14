using Pope, HDF5
using Pope.LJH
using Base.Test

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
    r = LJH.LJHRecord(1:1000,1,2)
    r3 = LJH.LJH3Record(1:1000,0,10,20)
    analyzer = Pope.BasisAnalyzer(rand(6,1000))
    dataproduct = analyzer(r)
    dataproduct3 = analyzer(r3)
    @test dataproduct.reduced == dataproduct3.reduced
    @test dataproduct.residual_std == dataproduct3.residual_std
    @test dataproduct.timestamp_usec == LJH.timestamp_usec(r)
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
    @test read(h5["1/residual_std"]) == [1]
    @test read(h5["1/samplecount"]) == [2]
    @test read(h5["1/timestamp_usec"]) == [3]
    @test read(h5["1/first_rising_sample"]) == [4]
    @test read(h5["1/nsamples"]) == [5]
    close(h5)
    rm(h5.filename)
end
