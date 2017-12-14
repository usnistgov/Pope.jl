
mutable struct BufferedHDF5Dataset2D{T}
  ds::HDF5Dataset
  v::Vector{Vector{T}} #naievley you want a 2d array here, but there is no
  # equivalent of push!, so it uses less copying to have a vector of vectors
  # see https://github.com/JuliaLang/julia/issues/10546
  lastrow::Int64 # last index in hdf5 dataset
end
BufferedHDF5Dataset2D(ds)= BufferedHDF5Dataset2D(ds, Vector{Vector{eltype(ds)}}(), 0)
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
    basis::Array{Float32,2}
end

struct BasisBufferedWriter <: DataSink
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

const basis_fieldnames = collect(fieldnames(BasisBufferedWriter)[4:end])
"    hdf5file(b::MassCompatibleBufferedWriters)
Return the filename of the hdf5 file associated with `b`."
hdf5file(b::BasisBufferedWriter) = file(b.residual_std.ds)
function write_to_hdf5(b::BasisBufferedWriter)
  write_to_hdf5.([b.residual_std, b.samplecount,
  b.timestamp_usec, b.first_rising_sample, b.nsamples])
end
function Base.write(b::BasisBufferedWriter,x::BasisDataProduct)
  write(d.reduced, x.reduced)
  write(d.residual_std, x.residual_std)
  write(d.samplecount, x.samplecount)
  write(d.timestamp_usec, x.timestamp_usec)
  write(d.first_rising_sample, x.first_rising_sample)
  write(d.nsamples, x.nsamples)
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
