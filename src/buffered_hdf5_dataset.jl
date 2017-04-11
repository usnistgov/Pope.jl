using HDF5

"HDF5 appears to be inefficent for small writes, so this a simple buffer that
allows me to write to HDF5 only once per unit time (typically one second) to
limit the number of small writes."
type BufferedHDF5Dataset{T}
  ds::HDF5Dataset
  v::Vector{T}
  lasti::Int64 # last index in hdf5 dataset
  timeout_s::Float64 # interval in seconds at which to transfer data from v to ds
  endchannel::Channel{Bool} # stop writing if this channel is ready
  task::Task
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

function Base.schedule(b::BufferedHDF5Dataset)
  b.task=@schedule begin
    while !isready(b.endchannel)
      write_to_hdf5(b)
      sleep(b.timeout_s)
    end
    write_to_hdf5(b)
  end
end
stop(b::BufferedHDF5Dataset) = put!(b.endchannel,true)
Base.wait(b::BufferedHDF5Dataset) = wait(b.task)

Base.write{T}(b::BufferedHDF5Dataset{T},x::T) = push!(b.v,x)
Base.write{T}(b::BufferedHDF5Dataset{T},x::Vector{T}) = append!(b.v,x)

function g_require(parent::Union{HDF5File,HDF5Group}, name)
	exists(parent,name) ? parent[name] : g_create(parent,name)
end

immutable MassCompatibleBufferedWriters
  filt_value        ::BufferedHDF5Dataset{Float32}
  filt_phase      ::BufferedHDF5Dataset{Float32}
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

function make_buffered_hdf5_writer(h5, channel_number,chunksize=1000, timeout_s=1.0)
  g = g_require(h5,"chan$channel_number")
  d=MassCompatibleBufferedWriters([BufferedHDF5Dataset(d_create(g, string(name), fieldtype(MassCompatibleDataProductFeb2017,name), ((1,), (-1,)), "chunk", (chunksize,)), Vector{fieldtype(MassCompatibleDataProductFeb2017,name)}(), 0,timeout_s, Channel{Bool}(1), @task nothing) for name in fieldnames(MassCompatibleBufferedWriters)]...)
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

Base.schedule(d::MassCompatibleBufferedWriters) = [schedule(getfield(d,s)) for s in fieldnames(MassCompatibleBufferedWriters)]
function Base.close(d::MassCompatibleBufferedWriters)
  for s in fieldnames(MassCompatibleBufferedWriters)
    stop(getfield(d,s))
  end
  wait(d)
end

function write_header(d::MassCompatibleBufferedWriters,ljh,analyzer::MassCompatibleAnalysisFeb2017)
  # this is called once per ljh file, but we only want to write to the
  # top level of the HDF5 file once
  a=attrs(d.filt_value.ds.file)
  if !("nsamples" in names(a))
    a["nsamples"]=ljh.record_nsamples
    a["npresamples"]=ljh.pretrig_nsamples
    a["frametime"]=ljh.frametime
  end
  # we can write to the group for this ljh file (eg chan13), other calls won't write to this group
  channelgroup = parent(d.filt_value.ds)
  g_create(channelgroup, "calculated_cuts")
  channelgroup["calculated_cuts"]["pretrigger_rms"]=analyzer.pretrigger_rms_cuts
  channelgroup["calculated_cuts"]["postpeak_deriv"]=analyzer.postpeak_deriv_cuts
  channelattrs = attrs(channelgroup)
  channelattrs["filename"]=ljh.filename
  channelattrs["analyzed by pope"]="true"
end
function (d::MassCompatibleBufferedWriters)(x::MassCompatibleDataProductFeb2017)
  write(d,x)
end
Base.wait(d::MassCompatibleBufferedWriters) = [wait(getfield(d,name).task) for name in fieldnames(typeof(d))]
