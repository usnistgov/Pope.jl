using HDF5

"""
    h5create(fname)

Create and return an hdf5 file at path `fname`. Files created by this function
will be compatible with `HDF5.start_swmr_write` and other Pope requirements."
"""
H5F_LIBVER_LATEST = 2 # in HDF5.jl 0.8.8 HDF5.H5F_LIBVER_LATEST has the wrong value, this is a temporary workaround
h5create(fname) = h5open(fname,"w", "libver_bounds", (H5F_LIBVER_LATEST, H5F_LIBVER_LATEST))
"""
    d_extend(d::HDF5Dataset, value::Vector, range::UnitRange)

Equivalent to `d[range]=value` on an extendible on dimensional HDF5Dataset `d` except
that the length of `d` is set to `maximum(range)` before writing.
"""
function d_extend(d::HDF5Dataset, value::Vector, range::UnitRange)
  set_dims!(d, (maximum(range),))
	d[range] = value
	d
end
"""
    g_require(parent::Union{HDF5File,HDF5Group}, name)

Return an HDF5Group with name `name` in `parent.` If the group does not exist, create it.
"""
function g_require(parent::Union{HDF5File,HDF5Group}, name)
	exists(parent,name) ? parent[name] : g_create(parent,name)
end

"""
    BufferedHDF5Dataset(ds::HDF5Dataset, v::Vector, lasti)

HDF5 appears to be inefficent for small writes, so this a simple buffer that
allows me to write to HDF5 only once per unit time (typically one second) to
limit the number of small writes. `MassCompatibleBufferedWriters` is based upon
`BufferedHDF5Dataset` and you can call `schedule` on an instand of `MassCompatibleBufferedWriters`
to set the write frequency.
"""
mutable struct BufferedHDF5Dataset{T}
  ds::HDF5Dataset
  v::Vector{T}
  lasti::Int64 # last index in hdf5 dataset
end
function BufferedHDF5Dataset{T}(g::Union{HDF5File,HDF5Group}, name, chunksize) where T
  ds = d_create(g, name, T, ((1,),(-1,)), "chunk", chunksize)
  BufferedHDF5Dataset{T}(ds, Vector{T}(), 0)
end
function write_to_hdf5(b::BufferedHDF5Dataset)
  r = b.lasti + (1:length(b.v))
  if length(r)>0
    d_extend(b.ds, b.v, r)
    empty!(b.v)
    b.lasti=last(r)
  end
  return
end
Base.write{T}(b::BufferedHDF5Dataset{T},x::T) = push!(b.v,x)
Base.write{T}(b::BufferedHDF5Dataset{T},x::Vector{T}) = append!(b.v,x)



abstract type BufferedWriter <: DataSink end
"""
    MassCompatibleBufferedWriters <: DataSink

Construct using `make_buffered_hdf5_writer(h5, channel_number, chunksize=1000, timeout_s=1.0)`.
Contains many `BufferedHDF5Dataset` and organizes writing to them. Supports
`schedule`, `stop`, `wait`, `close`, `flush`, `write`, `write_header`, `hdf5_file`,
`write_header_end`, `write_header_allchannel`. If you have an instance `d`,
then `d(x)` is equivalent to `write(d,x)`.
"""
mutable struct MassCompatibleBufferedWriters <: BufferedWriter
  endchannel        ::Channel{Bool}
  timeout_s         ::Float64
  task              ::Task
  filt_value        ::BufferedHDF5Dataset{Float32}
  filt_phase        ::BufferedHDF5Dataset{Float32}
  timestamp         ::BufferedHDF5Dataset{Float64}
  rowcount          ::BufferedHDF5Dataset{Int64}
  pretrig_mean      ::BufferedHDF5Dataset{Float32}
  pretrig_rms       ::BufferedHDF5Dataset{Float32}
  pulse_average     ::BufferedHDF5Dataset{Float32}
  pulse_rms         ::BufferedHDF5Dataset{Float32}
  rise_time         ::BufferedHDF5Dataset{Float32}
  postpeak_deriv    ::BufferedHDF5Dataset{Float32}
  peak_index        ::BufferedHDF5Dataset{UInt16}
  peak_value        ::BufferedHDF5Dataset{UInt16}
  min_value         ::BufferedHDF5Dataset{UInt16}
end
const mass_fieldnames = collect(fieldnames(MassCompatibleBufferedWriters)[4:end])
"    hdf5file(b::MassCompatibleBufferedWriters)
Return the filename of the hdf5 file associated with `b`."
hdf5file(b::MassCompatibleBufferedWriters) = file(b.filt_value.ds)
function write_to_hdf5(b::MassCompatibleBufferedWriters)
  write_to_hdf5.([b.filt_value, b.filt_phase, b.timestamp, b.rowcount, b.pretrig_mean, b.pretrig_rms, b.pulse_average,
  b.pulse_rms, b.rise_time, b.postpeak_deriv, b.peak_index, b.peak_value, b.min_value])
end
function Base.schedule(b::BufferedWriter)
  b.task=@schedule begin
    while !isready(b.endchannel)
      write_to_hdf5(b)
      sleep(b.timeout_s)
    end
    write_to_hdf5(b)
  end
end
stop(b::BufferedWriter) = put!(b.endchannel,true)
Base.wait(b::BufferedWriter) = wait(b.task)
Base.close(b::BufferedWriter) = (stop(b);wait(b))
Base.flush(b::BufferedWriter) = flush(hdf5file(b))
function make_buffered_hdf5_writer(h5, channel_number, analzyer::MassCompatibleAnalysisFeb2017, chunksize=1000, timeout_s=1.0)
  g = g_require(h5,"chan$channel_number")
  d=MassCompatibleBufferedWriters(Channel{Bool}(1), timeout_s, Task(nothing),
   [BufferedHDF5Dataset{fieldtype(MassCompatibleDataProductFeb2017,name)}(g,
       string(name), chunksize) for name in mass_fieldnames]...)
  schedule(d)
  d
end

function Base.write(d::MassCompatibleBufferedWriters,x::MassCompatibleDataProductFeb2017)
  write(d.filt_value, x.filt_value)
  write(d.filt_phase, x.filt_phase)
  write(d.timestamp, x.timestamp)
  write(d.rowcount, x.rowcount)
  write(d.pretrig_mean, x.pretrig_mean)
  write(d.pretrig_rms, x.pretrig_rms)
  write(d.pulse_average, x.pulse_average)
  write(d.pulse_rms, x.pulse_rms)
  write(d.rise_time, x.rise_time)
  write(d.postpeak_deriv, x.postpeak_deriv)
  write(d.peak_index, x.peak_index)
  write(d.peak_value, x.peak_value)
  write(d.min_value, x.min_value)
end

function write_header(d::MassCompatibleBufferedWriters,r::LJHReaderFeb2017)
  channelgroup = parent(d.filt_value.ds)
  g_create(channelgroup, "calculated_cuts")
  channelgroup["calculated_cuts"]["pretrig_rms"]=r.analyzer.pretrigger_rms_cuts
  channelgroup["calculated_cuts"]["postpeak_deriv"]=r.analyzer.postpeak_deriv_cuts
  channelattrs = attrs(channelgroup)
  channelattrs["filename"]=r.fname
  channelattrs["pope_preknowledge_file"]=r.analyzer.pk_filename
  channelattrs["channum"]=LJH.channel(r.fname)
  channelattrs["noise_filename"]="analyzed by pope, see `pope_preknowledge_file`"
end
function write_header_end(d::MassCompatibleBufferedWriters,ljh,analyzer::MassCompatibleAnalysisFeb2017)
  # dont add datasets, groups or attributes after SWMR writing is started
  # channelgroup = parent(d.filt_value.ds)
  # channelattrs = attrs(channelgroup)
  # # when write_header_end is called, some values may not be flushed to hdf5 yet
  # # so I add lasti (number pulses written to hdf5) + length(v) (number pulses to be written)
  # channelattrs["npulses"]=d.filt_value.lasti+length(d.filt_value.v)
end
"""
    write_header_allchannel(d::MassCompatibleBufferedWriters, r::LJHReaderFeb2017)

Write "header" information assocaited with all channels to an hdf5 file.
This function is only called once per ljh file, not once per channel.
Also calls `start_swmr_write`. Remember all datasets, groups, and attributes must exist before
calling `start_swmr_write`.
"""
function write_header_allchannel(d::MassCompatibleBufferedWriters, r::LJHReaderFeb2017)
  h5 = hdf5file(d)
  a = attrs(h5)
  # execute only once for the whole HDF5 file
  "nsamples" in names(a) && error("only call_write_header_allchannels once per ljh file set, not once per channel")
  a["nsamples"]=r.analyzer.nsamples
  a["npresamples"]=r.analyzer.npresamples
  a["frametime"]=r.analyzer.frametime
  flush(h5)
  try
    HDF5.start_swmr_write(h5)
  catch
    println("SKIPPING START_SWMR_WRITE, HDF5 VERSION TOO LOW")
  end
end
# function (d::T)(x) where T<:BufferedWriter
#   write(d,x)
# end
