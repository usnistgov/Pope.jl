module Pope
using HDF5, ProgressMeter, ZMQ, TypedDelegation
include("LJH.jl")
include("ljhutil.jl")
include("summarize.jl")
include("apply_filter.jl")
include("matter_simulator.jl")
include("zmq_datasink.jl")
include("ports.jl")

"Readers{T}"
type Readers{T} <: AbstractVector{T}
  v::Vector{T}
  headers_done::Bool
  endchannel::Channel{Bool}
end
@delegate_oneField(Readers, v, [Base.push!, Base.length, Base.size, Base.eltype, Base.start, Base.next, Base.done, Base.endof, Base.setindex!, Base.getindex])
# # Base.schedule(r::Readers) = schedule.(r.v)
# stop(r::Readers) = stop.(r.v)
# Base.wait(r::Readers) = wait.(r.v)
Readers(v) = Readers(v,false,Channel{Bool}(1))

"LJHReaderFeb2017{T1,T2}(fname, analyzer::T1, product_writer::T2, timeout_s, progress_meter) = LJHReaderFeb2017{T1,T2}(fname, analyzer::T1, product_writer::T2, timeout_s, progress_meter)
If `r` is an instances you can
`schedule(r.task)` to start reader
`stop(r)` to tell the reader to finish up
`wait(r)` to wait on r.task, which will exit after the analysis finishes up
It is probably better to use `launch_reader` than to call this directly
"
type LJHReaderFeb2017{T1,T2}
  status::String
  fname::String
  ljh::Nullable{LJH.LJHFile}
  analyzer::T1
  product_writer::T2
  timeout_s::Float64
  endchannel::Channel{Bool}
  progress_meter::Bool # only use this on static ljh files
  task::Task
  function LJHReaderFeb2017(fname, analyzer::T1, product_writer::T2, timeout_s, progress_meter)
    this = new("initialized",fname, Nullable{LJH.LJHFile}(), analyzer, product_writer, timeout_s, Channel{Bool}(1), progress_meter)
    task = @task this()
    this.task=task
    this
  end
end
LJHReaderFeb2017{T1,T2}(fname, analyzer::T1, product_writer::T2, timeout_s, progress_meter) = LJHReaderFeb2017{T1,T2}(fname, analyzer::T1, product_writer::T2, timeout_s, progress_meter)
Base.schedule(r::LJHReaderFeb2017) = schedule(r.task)
function stop(r::LJHReaderFeb2017)
  !isready(r.endchannel) && put!(r.endchannel,true)
end
Base.wait(r::LJHReaderFeb2017) = wait(r.task)

function (r::LJHReaderFeb2017)()
  fname, analyzer, product_writer, endchannel, timeout_s = r.fname, r.analyzer, r.product_writer, r.endchannel, r.timeout_s
  file_exist = wait_for_file_to_exist(fname,r.endchannel)
  if !file_exist
    r.status = "file did not exist before was instructed to end"
    return
  end
  ljh = LJH.LJHFile(fname)
  check_compatability(analyzer, ljh)
  r.ljh = Nullable(ljh)
  if r.progress_meter
    progress_meter = Progress(length(ljh))
    i=0
  end
  #@show r.ljh
  write_header(product_writer, ljh, r.analyzer)
  r.status = "running"
  while true
    while true # read and process all data
      data=LJH.tryread(ljh)
      isnull(data) && break
      analysis_products = analyzer(get(data))
      write(product_writer,analysis_products)
      r.progress_meter && next!(progress_meter)
    end
    isready(endchannel) && break
    # watch_file(ljh,timeout_s)
    sleep(timeout_s)
  end
  write_header_end(product_writer, ljh, r.analyzer)
  close(ljh)
  close(product_writer)
  r.status = "done"
end




"create an LJHReaderFeb2017.
If `continuous` is true is will continue trying to read from `fname` until something does
`put!(reader.endchannel,true)`. If it `continuous` is false, it will stop as soon as it reads all data in the file."
function make_reader(fname, analyzer, product_writer; continuous=true, timeout_s=1, progress_meter=!continuous)
  reader = LJHReaderFeb2017(fname, analyzer, product_writer, timeout_s, progress_meter)
  !continuous && put!(reader.endchannel,true)
  reader
end

immutable MassCompatibleAnalysisFeb2017
  filter::Vector{Float64} # single lag filter
  filter_at::Vector{Float64} # single lag filter arrival time component
  npresamples::Int64 # number of sample trigger
  nsamples::Int64 # length of pulse in sample
  peak_index::Int64 # peak index of average pulse, look for postpeak_deriv after this
  frametime::Float64 # time between two samples in seconds
  shift_threshold::Int64
  pretrigger_rms_cuts::Vector{Float64} # lower and upper limit cut for pretrigger_rms
  postpeak_deriv_cuts::Vector{Float64} # lower and upper limit cut for postpeak_deriv
  pk_filename::String
end

abstract DataProduct
immutable MassCompatibleDataProductFeb2017 <: DataProduct
  filt_value        ::Float32
  filt_phase        ::Float32
  timestamp         ::Float64
  rowcount          ::Int64
  pretrig_mean      ::Float32
  pretrig_rms       ::Float32
  pulse_average     ::Float32
  pulse_rms         ::Float32
  rise_time         ::Float32
  postpeak_deriv    ::Float32
  peak_index        ::UInt16
  peak_value        ::UInt16
  min_value         ::UInt16
end
function Base.write(io::IO, d::MassCompatibleDataProductFeb2017)
  write(io, reinterpret(UInt8,[d]))
end
function check_compatability(a::MassCompatibleAnalysisFeb2017, ljh::LJH.LJHFile)
  ljh.record_nsamples == a.nsamples || error("Channel $(ljh.channum) has $(ljh.record_nsamples) samples, anlyzer has $(a.nsamples).")
  ljh.pretrig_nsamples == a.npresamples || error("Channel $(ljh.channum) has $(ljh.pretrig_nsamples) pretrigger samples, anlyzer has $(a.npresamples).")
  ljh.frametime == a.frametime || error("Channel $(ljh.channum) has $(ljh.frametime) frametime, anlyzer has $(a.frametime).")
end
function (a::MassCompatibleAnalysisFeb2017)(record::LJH.LJHRecord)
  summary = summarize(record.data, a.npresamples,a.nsamples, a.peak_index, a.frametime)
  filt_phase, filt_value = filter_single_lag(record.data, a.filter, a.filter_at, summary.pretrig_mean, a.npresamples, a.shift_threshold)
  MassCompatibleDataProductFeb2017(filt_value, filt_phase, record.timestamp_usec/1e6, record.rowcount,
  summary.pretrig_mean, summary.pretrig_rms, summary.pulse_average, summary.pulse_rms, summary.rise_time,
  summary.postpeak_deriv, summary.peak_index, summary.peak_value,summary.min_value )
end

"asbstract DataSink
subtype `T` must have methods:
`write(ds::T, dp::S)` where `S` is a subtype of DataProduct
`write_header(ds, ljh, analyzer)` where ljh is an LJHFile, and analyzer is a MassCompatibleAnalysisFeb2017
`write_header_end(ds,ljh,analyzer)` which amends the header after all writing is finalized
for things like number of records that are only known after all writing
`close(ds)`"
abstract DataSink
immutable DataWriter <: DataSink
  f::IOStream
end
Base.write(dw::DataWriter,x...) = write(dw.f,x...)
function (dw::DataWriter)(d::MassCompatibleDataProductFeb2017)
  write(dw,d)
end
Base.close(dw::DataWriter) = close(dw.f)
function write_header_end(dw::DataWriter,f::LJH.LJHFile, analzyer::MassCompatibleAnalysisFeb2017)
end
function write_header(dw::DataWriter,f::LJH.LJHFile, analzyer::MassCompatibleAnalysisFeb2017)
  # dump(dw.f,Pope.MassCompatibleDataProductFeb2017)
  # write(dw, "from file: $f.filename\n")
  # write(dw,"HEADER DONE\n")
end

"`ds=MultipleDataSink((a,b))` or `ds=MultipleDataSink(a,b)`
creates a type where `write(ds,x)` writes to both `a` and `b`
likewise for `close`, `write_header` and `write_header_end`"
immutable MultipleDataSink{T} <: DataSink
  t::T
end
MultipleDataSink(x...) = MultipleDataSink(x)
function Base.write(mds::MultipleDataSink, x...)
  for ds in mds.t
    write(ds,x...)
  end
end
Base.close(mds::MultipleDataSink) = map(close,mds.t)
function write_header(mds::MultipleDataSink, ljh, analyzer)
  for ds in mds.t
    write_header(ds,ljh,analyzer)
  end
end
function write_header_end(mds::MultipleDataSink, ljh, analyzer)
  for ds in mds.t
    write_header_end(ds,ljh,analyzer)
  end
end



"wait_for_file_to_exist(fname, endchannel::Channel{Bool})
Blocks until either `fname` exists, or `isready(endchannel)`. returns true if `fname` exists and false otherwise."
function wait_for_file_to_exist(fname, endchannel::Channel{Bool})
  sleeptime = 1.0
  while true
    isfile(fname) && return true
    sleep(sleeptime)
    isready(endchannel) && return false
  end
end

function analyzer_from_preknowledge(pk::HDF5Group)
  MassCompatibleAnalysisFeb2017(pk["filter"]["values"][:], pk["filter"]["values_at"][:], read(pk["trigger"]["npresamples"]),
  read(pk["trigger"]["nsamples"]), read(pk["summarize"]["peak_index"]), read(pk["physical"]["frametime"]),read(pk["filter"]["shift_threshold"]),
  read(pk["cuts"]["postpeak_deriv"]), read(pk["cuts"]["postpeak_deriv"]), filename(pk)
  )
end

include("buffered_hdf5_dataset.jl")


end # module
