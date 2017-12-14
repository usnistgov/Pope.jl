"    BufferedHDF5Dataset2D{T}(g::Union{HDF5File,HDF5Group}, name, nbases, chunksize)"
mutable struct BufferedHDF5Dataset2D{T}
  ds::HDF5Dataset
  v::Vector{Vector{T}} #naievley you want a 2d array here, but there is no
  # equivalent of push!, so it uses less copying to have a vector of vectors
  # see https://github.com/JuliaLang/julia/issues/10546
  lastrow::Int64 # last index in hdf5 dataset
end
function BufferedHDF5Dataset2D{T}(g::Union{HDF5File,HDF5Group}, name, nbases, chunksize) where T
  ds = d_create(g, name, T, ((nbases,1), (nbases,-1)), "chunk", (nbases,chunksize))
  BufferedHDF5Dataset2D{T}(ds, Vector{Vector{T}}(),0)
end
function write_to_hdf5(b::BufferedHDF5Dataset2D)
  r = b.lastrow + (1:length(b.v))
  if length(r)>0
    set_dims!(b.ds, (size(b.ds,1), last(r)) )
    b.ds[:,r] = hcat(b.v...)
    empty!(b.v)
    b.lastrow=last(r)
  end
  return
end
Base.write(b::BufferedHDF5Dataset2D{T},x::Vector{T}) where T = push!(b.v,x)
Base.write(b::BufferedHDF5Dataset2D{T},x::Vector{Vector{T}}) where T = append!(b.v,x)

# d_create(h5, "ds", Float32, ((6,1), (6,-1)), "chunk", (6,chunksize))
# a single pulse is stored in a column, and accessed a[:,1]

struct BasisDataProduct <: DataProduct
    reduced::Vector{Float32} # reduced pulse, aka projection of pulse into subspace defined by basis
    residual_std::Float32
    samplecount::Int
    timestamp_usec::Int
    first_rising_sample::UInt32
    nsamples::UInt32
end

struct BasisAnalyzer
    basis::Array{Float32,2} # size (nbasis,nsamples)
end
function (a::BasisAnalyzer)(record::LJH.LJHRecord)
  reduced = a.basis*record.data
  data_subspace = a.basis'*reduced
  residual_std = std(data_subspace-record.data)
  BasisDataProduct(reduced, residual_std, LJH.rowcount(record),
    LJH.timestamp_usec(record), 0, length(record))
end
function (a::BasisAnalyzer)(record::LJH.LJH3Record)
  reduced = a.basis*record.data
  data_subspace = a.basis'*reduced
  residual_std = std(data_subspace-record.data)
  BasisDataProduct(reduced, residual_std, LJH.samplecount(record),
    LJH.timestamp_usec(record), LJH.first_rising_sample(record), length(record))
end

mutable struct BasisBufferedWriter <: BufferedWriter
    endchannel           ::Channel{Bool}
    timeout_s            ::Float64
    task                 ::Task
    reduced              ::BufferedHDF5Dataset2D{Float32}
    residual_std         ::BufferedHDF5Dataset{Float32}
    samplecount          ::BufferedHDF5Dataset{Int}
    timestamp_usec       ::BufferedHDF5Dataset{Int}
    first_rising_sample  ::BufferedHDF5Dataset{UInt32}
    nsamples             ::BufferedHDF5Dataset{UInt32}
end
function BasisBufferedWriter(h5::HDF5File, channel_number, nbases, chunksize, timeout_s;start=true)
  BasisBufferedWriter(g_create(h5,"$channel_number"),nbases,chunksize,timeout_s,start=start)
end
function BasisBufferedWriter(g::HDF5Group, nbases, chunksize, timeout_s;start=true)
  b=BasisBufferedWriter(Channel{Bool}(1), timeout_s, Task(nothing),
  BufferedHDF5Dataset2D{Float32}(g,"reduced", nbases, chunksize),
  BufferedHDF5Dataset{Float32}(g,"residual_std", chunksize),
  BufferedHDF5Dataset{Int}(g,"samplecount", chunksize),
  BufferedHDF5Dataset{Int}(g,"timestamp_usec", chunksize),
  BufferedHDF5Dataset{UInt32}(g,"first_rising_sample", chunksize),
  BufferedHDF5Dataset{UInt32}(g,"nsamples", chunksize), )
  start && schedule(b)
  b
end
"    hdf5file(b::MassCompatibleBufferedWriters)
Return the filename of the hdf5 file associated with `b`."
hdf5file(b::BasisBufferedWriter) = file(b.residual_std.ds)
function write_to_hdf5(b::BasisBufferedWriter)
  write_to_hdf5(b.reduced);write_to_hdf5(b.residual_std);write_to_hdf5(b.samplecount)
  write_to_hdf5(b.timestamp_usec);write_to_hdf5(b.first_rising_sample);write_to_hdf5(b.nsamples)
end
function Base.write(b::BasisBufferedWriter,x::BasisDataProduct)
  write(b.reduced, x.reduced)
  write(b.residual_std, x.residual_std)
  write(b.samplecount, x.samplecount)
  write(b.timestamp_usec, x.timestamp_usec)
  write(b.first_rising_sample, x.first_rising_sample)
  write(b.nsamples, x.nsamples)
  return nothing
end

function write_header(d::BasisBufferedWriter,r)
  channelgroup = parent(d.filt_value.ds)
  channelgroup["header"]="header"
end
function write_header_end(d::BasisBufferedWriter,ljh,analyzer::MassCompatibleAnalysisFeb2017)
  # dont add datasets, groups or attributes after SWMR writing is started
  # channelgroup = parent(d.filt_value.ds)
  # channelattrs = attrs(channelgroup)
end
function write_header_allchannel(d::BasisBufferedWriter, r)
  h5 = hdf5file(d)
  h5["jointheader"]="jointheader"
  # execute only once for the whole HDF5 file
  flush(h5)
  try
    HDF5.start_swmr_write(h5)
  catch
    println("SKIPPING START_SWMR_WRITE, HDF5 VERSION TOO LOW")
  end
end
