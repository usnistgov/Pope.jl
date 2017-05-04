module Pope
using HDF5, ProgressMeter, ZMQ, TypedDelegation
include("LJH.jl")
include("ljhutil.jl")
include("summarize.jl")
include("apply_filter.jl")
include("matter_simulator.jl")
include("zmq_datasink.jl")
include("ports.jl")

"Readers is like a Vector{LJHReaderFeb2017} with some additional smarts for
contruct it with `rs=Readers()`
then `push!` in intances of `LJHReaderFeb2017`
then `schedule(rs)`
later `stop(rs)` and if you want `wait(rs)`
"
type Readers{T} <: AbstractVector{T}
  v::Vector{T}
  endchannel::Channel{Bool}
  task::Task
  timeout_s::Float64
end
@delegate_oneField(Readers, v, [Base.length, Base.size, Base.eltype, Base.start, Base.next, Base.done, Base.endof, Base.setindex!, Base.getindex])
Base.push!(rs::Readers,x) = (push!(rs.v,x);rs)
Readers() = Readers(LJHReaderFeb2017[],Channel{Bool}(1), Task(nothing), 1.0)
function write_headers(rs::Readers)
  for r in rs
    write_header(r)
  end
  r=first(rs)
  write_header_allchannel(r)
  rs.task = @schedule begin
    while !isready(rs.endchannel)
      sleep(rs.timeout_s)
      flush(r.product_writer) # this task flushes the HDF5 file backing the product writer once per timeout_s
    end
    flush(r.product_writer)
    end
end
function Base.schedule(rs::Readers)
  write_headers(rs)
  schedule.(rs)
end
"stop(rs::Readers) Tell all tasks in `rs` and in contents to stop. `wait(rs)` blocks until all tasks are complete."
function stop(rs::Readers)
  put!(rs.endchannel,true)
  stop.(rs.v)
end
function Base.wait(rs::Readers)
  wait(rs.task)
  wait.(rs.v)
end

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
stop(r::LJHReaderFeb2017) =   !isready(r.endchannel) && put!(r.endchannel,true)
Base.wait(r::LJHReaderFeb2017) = wait(r.task)
write_header(r::LJHReaderFeb2017) = write_header(r.product_writer, r)
function write_header_allchannel(r::LJHReaderFeb2017)
  write_header_allchannel(r.product_writer, r)
end

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
    ch = LJHUtil.channel(r.fname)
    progress_meter = Progress(length(ljh),0.25,"Channel $ch Progress: ")
    progress_meter.tlast -= 1 # make sure it prints at least once by setting tlast back by one second
    i=0
  end
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
`put!(reader.endchannel,true)`."
function make_reader(fname, analyzer, product_writer ; timeout_s=1, progress_meter=false)
  reader = LJHReaderFeb2017(fname, analyzer, product_writer, timeout_s, progress_meter)
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
`write_header(ds::T, f::LJHReaderFeb2017)`
`write_header_allchannel(ds::T, f::LJHReaderFeb2017)`
`write_header_end(ds::T,ljh,analyzer)`
`flush(ds::T)``
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
function write_header(dw::DataWriter,r::LJHReaderFeb2017)
  # dump(dw.f,Pope.MassCompatibleDataProductFeb2017)
  # write(dw, "from file: $f.filename\n")
  # write(dw,"HEADER DONE\n")
end
write_header_allchannel(dw::DataWriter, r::LJHReaderFeb2017) = nothing
Base.flush(dw::DataWriter) = flush(dw.f)

"`ds=MultipleDataSink((a,b))` or `ds=MultipleDataSink(a,b)`
creates a type where `write(ds,x)` writes to both `a` and `b`
likewise for `close`, `write_header` and `write_header_end`"
immutable MultipleDataSink{T<:Tuple} <: DataSink
  t::T
end
MultipleDataSink(x...) = MultipleDataSink(x)
function Base.write(mds::MultipleDataSink, x...)
  for ds in mds.t
    write(ds,x...)
  end
end
Base.close(mds::MultipleDataSink) = map(close,mds.t)
function write_header(mds::MultipleDataSink, x...)
  for ds in mds.t
    write_header(ds,x...)
  end
end
function write_header_end(mds::MultipleDataSink, x...)
  for ds in mds.t
    write_header_end(ds,x...)
  end
end
Base.flush(mds::MultipleDataSink) = map(flush, mds.t)
function write_header_allchannel(mds::MultipleDataSink, x...)
  for ds in mds.t
    write_header_allchannel(ds,x...)
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
