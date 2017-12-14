using Pope, HDF5
using Base.Test
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
