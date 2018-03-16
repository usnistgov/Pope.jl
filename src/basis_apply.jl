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
    frame1index::Int
    timestamp_usec::Int
    first_rising_sample::Int32
    nsamples::Int32
end
function Base.write(io::IO, d::BasisDataProduct)
  write(io, d.reduced)
  write(io, d.residual_std)
  write(io, d.frame1index)
  write(io, d.timestamp_usec)
  write(io, d.first_rising_sample)
  write(io, d.nsamples)
end

"""
An implementaion of AbstractBasisAnalyzer must have a field `projectors` that is an array with size ``(nbases, nsamples)` such that
the reduced pulse is calculated as `projectors*data` where `data` is a `Vector` of with length `nsamples`. It must also overload calling itself
to call `record2dataproduct`. See Julia issue #14919 for why this is neccesary.
"""
abstract type AbstractBasisAnalyzer end
struct BasisAnalyzer <: AbstractBasisAnalyzer
    projectors::Array{Float32,2} # size (nbases,nsamples)
    basis::Array{Float32,2} # size (nsamples,nbases)
    BasisAnalyzer(a) = new(a,a')
end
nbases(a::AbstractBasisAnalyzer) = size(a.projectors,2)
check_compatability(a::AbstractBasisAnalyzer, ljh) = nothing
(a::BasisAnalyzer)(record) = record2dataproduct(a,record)
modelreduce(a::AbstractBasisAnalyzer,data::AbstractVector)=a.projectors*data
modelpulse(a::AbstractBasisAnalyzer,reduced)=a.basis*reduced

function record2dataproduct(a::AbstractBasisAnalyzer,record::Union{LJH.LJHRecord, LJH.LJH3Record})
  reduced = modelreduce(a,LJH.data(record))
  modeled = modelpulse(a,reduced)
  residual_std = std(modeled-LJH.data(record))
  BasisDataProduct(reduced, residual_std, LJH.frame1index(record),
    LJH.timestamp_usec(record), LJH.first_rising_sample(record), length(record))
end

mutable struct BasisBufferedWriter <: BufferedWriter
    endchannel           ::Channel{Bool}
    timeout_s            ::Float64
    task                 ::Task
    reduced              ::BufferedHDF5Dataset2D{Float32}
    residual_std         ::BufferedHDF5Dataset{Float32}
    frame1index          ::BufferedHDF5Dataset{Int}
    timestamp_usec       ::BufferedHDF5Dataset{Int}
    first_rising_sample  ::BufferedHDF5Dataset{Int32}
    nsamples             ::BufferedHDF5Dataset{Int32}
end
function BasisBufferedWriter(h5::HDF5File, channel_number, nbases, chunksize, timeout_s;start=true)
  BasisBufferedWriter(g_create(h5,"$channel_number"),nbases,chunksize,timeout_s,start=start)
end
function BasisBufferedWriter(g::HDF5Group, nbases, chunksize, timeout_s;start=true)
  b=BasisBufferedWriter(Channel{Bool}(1), timeout_s, Task(nothing),
  BufferedHDF5Dataset2D{Float32}(g,"reduced", nbases, chunksize),
  BufferedHDF5Dataset{Float32}(g,"residual_std", chunksize),
  BufferedHDF5Dataset{Int}(g,"frame1index", chunksize),
  BufferedHDF5Dataset{Int}(g,"timestamp_usec", chunksize),
  BufferedHDF5Dataset{Int32}(g,"first_rising_sample", chunksize),
  BufferedHDF5Dataset{Int32}(g,"nsamples", chunksize), )
  start && schedule(b)
  b
end
"    hdf5file(b::BasisBufferedWriter)
Return the filename of the hdf5 file associated with `b`."
hdf5file(b::BasisBufferedWriter) = file(b.residual_std.ds)
function write_to_hdf5(b::BasisBufferedWriter)
  write_to_hdf5(b.reduced);write_to_hdf5(b.residual_std);write_to_hdf5(b.frame1index)
  write_to_hdf5(b.timestamp_usec);write_to_hdf5(b.first_rising_sample);write_to_hdf5(b.nsamples)
end
function Base.write(b::BasisBufferedWriter,x::BasisDataProduct)
  write(b.reduced, x.reduced)
  write(b.residual_std, x.residual_std)
  write(b.frame1index, x.frame1index)
  write(b.timestamp_usec, x.timestamp_usec)
  write(b.first_rising_sample, x.first_rising_sample)
  write(b.nsamples, x.nsamples)
  return nothing
end

function write_header(d::BasisBufferedWriter,r)
  channelgroup = parent(d.residual_std.ds)
  channelgroup["header"]="header"
end
function write_header_end(d::BasisBufferedWriter,ljh,analyzer::AbstractBasisAnalyzer)
  # dont add datasets, groups or attributes after SWMR writing is started
  # channelgroup = parent(d.filt_value.ds)
  # channelattrs = attrs(channelgroup)
end
function write_header_allchannel(d::BasisBufferedWriter, r::LJHReaderFeb2017)
  # should be called exact once when `schedule` is called on a Readers
  h5 = hdf5file(d)
  h5["BasisBufferedWriterHeader"]="BasisBufferedWriterHeader"
  h5["jointheader"]="jointheader"
  # execute only once for the whole HDF5 file
  flush(h5)
  try
    HDF5.start_swmr_write(h5)
  catch
    println("SKIPPING START_SWMR_WRITE, HDF5 VERSION TOO LOW")
  end
end

function make_buffered_hdf5_writer(h5, channel_number, analyzer::AbstractBasisAnalyzer, chunksize=1000, timeout_s=1.0)
  g = g_require(h5,"$channel_number")
  BasisBufferedWriter(g,nbases(analyzer), chunksize, timeout_s,start=true)
end
