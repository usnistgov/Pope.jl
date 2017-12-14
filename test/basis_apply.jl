using Pope, HDF5
using Pope.LJH
using Base.Test

@testset "BufferedHDF5Dataset2D" begin
    h5 = h5open(tempname(),"w")
    const chunksize = 100
    # create an extendible dataset to hold reduced pulses with 6 element basis
    ds=d_create(h5, "ds", Float32, ((6,1), (6,-1)), "chunk", (6,chunksize))
    buffer = Pope.BufferedHDF5Dataset2D(ds)
    write(buffer, Vector{Float32}(1:6))
    write(buffer, Vector{Float32}(7:12))
    write(buffer, [Vector{Float32}(13:18), Vector{Float32}(19:24)])
    Pope.write_to_hdf5(buffer)
    @test read(ds) == reshape(Vector{Float32}(1:24),(6,4))
    close(h5)
    rm(h5.filename)
end

@test "BasisAnalyzer" begin
    r = LJH.LJHRecord(1:1000,1,2)
    r3 = LJH.LJH3Record(1:1000,0,10,20)
    analyzer = Pope.BasisAnalyzer(rand(6,1000))
    dataproduct = analyzer(r)
    dataproduct3 = analyzer(r3)
    @test dataproduct.reduced == dataproduct3.reduced
    @test dataproduct.residual_std == dataproduct3.residual_std
    @test dataproduct.timestamp_usec == LJH.timestamp_usec(r)
end
