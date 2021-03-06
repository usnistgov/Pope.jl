module Pope
using HDF5, ProgressMeter, Distributions, DataStructures
using Nullables
include("LJH.jl")
include("ljhutil.jl")
include("NoiseAnalysis.jl")
include("projections.jl")


"Readers is like a `Vector{LJHReaderFeb2017}` with some additional smarts for
contruct it with `rs=Readers()`
then `push!` in intances of `LJHReaderFeb2017`
then `schedule(rs)`
later `stop(rs)` and if you want `wait(rs)`LJH.
"
mutable struct Readers{T} <: AbstractVector{T}
  v::Vector{T}
  endchannel::Channel{Bool}
  task::Task
  timeout_s::Float64
end
DataStructures.@delegate Readers.v [Base.length, Base.size, Base.eltype, Base.iterate, Base.lastindex, Base.setindex!, Base.getindex]
Base.push!(rs::Readers,x) = (push!(rs.v,x);rs)
Readers() = Readers(LJHReaderFeb2017[],Channel{Bool}(1), Task(nothing), 1.0)
function write_headers(rs::Readers)
    for reader in rs
        write_header(reader)
    end
    r=first(rs)
    write_header_allchannel(r)
    rs.task = @async begin
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
"wait(rs::Readers) Call after `stop`. Waits until all tasks associated with `rs` are done."
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
mutable struct LJHReaderFeb2017{T1,T2}
  status::String
  fname::String
  ljh::Nullable{Union{LJH.LJHFile, LJH.LJH3File}}
  analyzer::T1
  product_writer::T2
  timeout_s::Float64
  endchannel::Channel{Bool}
  progress_meter::Bool # only use this on static ljh files
  task::Task
  function LJHReaderFeb2017{T1,T2}(fname, analyzer::T1, product_writer::T2, timeout_s, progress_meter) where {T1,T2}
    this = new("initialized",fname, Nullable{LJH.LJHFile}(), analyzer, product_writer, timeout_s, Channel{Bool}(1), progress_meter)
    task = @task this()
    this.task=task
    this
  end
end
LJHReaderFeb2017(fname, analyzer::T1, product_writer::T2, timeout_s, progress_meter) where {T1, T2} =
    LJHReaderFeb2017{T1, T2}(fname, analyzer::T1, product_writer::T2, timeout_s, progress_meter)
Base.schedule(r::LJHReaderFeb2017) = schedule(r.task)
stop(r::LJHReaderFeb2017) = !isready(r.endchannel) && put!(r.endchannel,true)
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
  ljh = LJH.ljhopen(fname)
  check_compatability(analyzer, ljh)
  r.ljh = Nullable(ljh)
  if r.progress_meter
    ch = LJH.channel(r.fname)
    progress_meter = Progress(LJH.progresssize(ljh),0.25,"Channel $ch: ")
    progress_meter.tlast -= 1 # make sure it prints at least once by setting tlast back by one second
  else
    progress_meter = Progress(1,0.25,"POPE SHOULDNT SHOW THIS!")
    next!(progress_meter) # immediatley finish it
  end
  r.status = "running"
  _ljhreaderfeb2017_coreloop(ljh, analyzer, product_writer, progress_meter,
    r.progress_meter, endchannel, timeout_s)
  write_header_end(product_writer, ljh, r.analyzer)
  close(ljh)
  close(product_writer)
  r.status = "done"
end
"    _ljhreaderfeb2017_coreloop(ljh,analyzer,product_writer,progress_meter,  progress_meter_enable, endchannel, timeout_s)
Internal use only, used to introduce a function barrier in `function (r::LJHReaderFeb2017)()`
so that the core loop is type stable."
function _ljhreaderfeb2017_coreloop(ljh,analyzer,product_writer,progress_meter,
  progress_meter_enable, endchannel, timeout_s)
  while true
    while true # read and process all data
      data=LJH.tryread(ljh)
      isnull(data) && break
      analysis_products = analyzer(get(data))
      write(product_writer,analysis_products)
      if progress_meter_enable
        ProgressMeter.update!(progress_meter, LJH.progressposition(ljh))
      end
    end
    isready(endchannel) && break
    sleep(timeout_s)
  end
end



"    make_reader(fname, analyzer, product_writer ; timeout_s=1, progress_meter=false)
create an `LJHReaderFeb2017`. If `continuous` is true is will continue trying to read from `fname` until something does
`put!(reader.endchannel,true)`."
function make_reader(fname, analyzer, product_writer ; timeout_s=1, progress_meter=false)
  reader = LJHReaderFeb2017(fname, analyzer, product_writer, timeout_s, progress_meter)
  reader
end

struct MassCompatibleAnalysisFeb2017
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

abstract type DataProduct end
struct MassCompatibleDataProductFeb2017 <: DataProduct
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
"    check_compatability(a, ljh)
Where `a` is an analyzer, and `ljh` is a pulse record souce. Throw an error if incompatible.
Return value is not used."
function check_compatability(a::MassCompatibleAnalysisFeb2017, ljh::LJH.LJHFile)
  ljh.record_nsamples == a.nsamples || error("Channel $(ljh.channum) has $(ljh.record_nsamples) samples, anlyzer has $(a.nsamples).")
  LJH.pretrig_nsamples(ljh) == a.npresamples || error("Channel $(ljh.channum) has $(LJH.pretrig_nsamples(ljh)) pretrigger samples, anlyzer has $(a.npresamples).")
  LJH.frametime(ljh) == a.frametime || error("Channel $(ljh.channum) has $(LJH.pretrig_nsamples(frametime)) frametime, anlyzer has $(a.frametime).")
end
function (a::MassCompatibleAnalysisFeb2017)(record::LJH.LJHRecord)
  summary = summarize(record.data, a.npresamples,a.nsamples, a.peak_index, a.frametime)
  filt_phase, filt_value = filter_single_lag(record.data, a.filter, a.filter_at, summary.pretrig_mean, a.npresamples, a.shift_threshold)
  MassCompatibleDataProductFeb2017(filt_value, filt_phase, record.timestamp_usec/1e6, record.rowcount,
  summary.pretrig_mean, summary.pretrig_rms, summary.pulse_average, summary.pulse_rms, summary.rise_time,
  summary.postpeak_deriv, summary.peak_index, summary.peak_value,summary.min_value )
end

"abstract DataSink
subtype `T` must have methods:
`write(ds::T, dp::S)` where `S` is a subtype of DataProduct
`write_header(ds::T, f::LJHReaderFeb2017)`
`write_header_allchannel(ds::T, f::LJHReaderFeb2017)`
`write_header_end(ds::T,ljh,analyzer)`
`flush(ds::T)``
`close(ds)`"
abstract type DataSink end
struct DataWriter <: DataSink
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
struct MultipleDataSink{T} <: DataSink
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

function analyzer_from_preknowledge(pk::HDF5.DataFile)
  if "analysis_type" in names(pk) && read(pk["analysis_type"])=="mass compatible feb 2017"
    return MassCompatibleAnalysisFeb2017(pk["filter"]["values"][:], pk["filter"]["values_at"][:], read(pk["trigger"]["npresamples"]),
    read(pk["trigger"]["nsamples"]), read(pk["summarize"]["peak_index"]), read(pk["physical"]["frametime"]),read(pk["filter"]["shift_threshold"]),
    read(pk["cuts"]["pretrigger_rms"]), read(pk["cuts"]["postpeak_deriv"]), filename(pk)  )
  elseif "svdbasis" in names(pk)
    modelinfo = hdf5load(SVDBasisWithCreationInfo,pk)
    return modelinfo.svdbasis
  end
  error("failed to generate analyzer from preknowledge group $pk with names $(names(pk))")
end

include("buffered_hdf5_dataset.jl")
include("basis_apply.jl")
include("basis_creation.jl")

end # module
