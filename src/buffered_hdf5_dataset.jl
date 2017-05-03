using HDF5

"HDF5 appears to be inefficent for small writes, so this a simple buffer that
allows me to write to HDF5 only once per unit time (typically one second) to
limit the number of small writes."
type BufferedHDF5Dataset{T}
  ds::HDF5Dataset
  v::Vector{T}
  lasti::Int64 # last index in hdf5 dataset
end

function d_extend(d::HDF5Dataset, value::Vector, range::UnitRange)
  set_dims!(d, (maximum(range),))
	d[range] = value
	d
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

function g_require(parent::Union{HDF5File,HDF5Group}, name)
	exists(parent,name) ? parent[name] : g_create(parent,name)
end
type MassCompatibleBufferedWriters <: DataSink
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
hdf5file(b::MassCompatibleBufferedWriters) = file(b.filt_value.ds)
function write_to_hdf5(b::MassCompatibleBufferedWriters)
  write_to_hdf5.([b.filt_value, b.filt_phase, b.timestamp, b.rowcount, b.pretrig_mean, b.pretrig_rms, b.pulse_average,
  b.pulse_rms, b.rise_time, b.postpeak_deriv, b.peak_index, b.peak_value, b.min_value])
end
function Base.schedule(b::MassCompatibleBufferedWriters)
  b.task=@schedule begin
    while !isready(b.endchannel)
      write_to_hdf5(b)
      sleep(b.timeout_s)
    end
    write_to_hdf5(b)
  end
end
stop(b::MassCompatibleBufferedWriters) = put!(b.endchannel,true)
Base.wait(b::MassCompatibleBufferedWriters) = wait(b.task)
Base.close(b::MassCompatibleBufferedWriters) = (stop(b);wait(b))
Base.flush(b::MassCompatibleBufferedWriters) = flush(hdf5file(b))
function make_buffered_hdf5_writer(h5, channel_number, chunksize=1000, timeout_s=1.0)
  g = g_require(h5,"chan$channel_number")
  buffered_datasets = [BufferedHDF5Dataset(d_create(g, string(name), fieldtype(MassCompatibleDataProductFeb2017,name), ((1,), (-1,)), "chunk", (chunksize,)), Vector{fieldtype(MassCompatibleDataProductFeb2017,name)}(),0) for name in mass_fieldnames]
  d=MassCompatibleBufferedWriters(Channel{Bool}(1), timeout_s, Task(nothing), buffered_datasets...)
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
  channelattrs["channum"]=LJHUtil.channel(r.fname)
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
function (d::MassCompatibleBufferedWriters)(x::MassCompatibleDataProductFeb2017)
  write(d,x)
end
