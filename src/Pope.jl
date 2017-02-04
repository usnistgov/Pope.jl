module Pope
include("LJH.jl")
include("LJHUtil.jl")
include("summarize.jl")
include("apply_filter.jl")

type LJHReaderFeb2017{T1,T2}
  status::Symbol
  fname::String
  ljh::Nullable{LJH.LJHFile}
  analyzer::T1
  product_writer::T2
  timeout_s::Float64
  endchannel::Channel{Bool}
  task::Task
  function LJHReaderFeb2017(fname, analyzer::T1, product_writer::T2, timeout_s)
    this = new(:initizalied,fname, Nullable{LJH.LJHFile}(), analyzer, product_writer, timeout_s, Channel{Bool}(1))
    task = @task this()
    this.task=task
    this
  end
end
LJHReaderFeb2017{T1,T2}(fname, analyzer::T1, product_writer::T2, timeout_s) = LJHReaderFeb2017{T1,T2}(fname, analyzer::T1, product_writer::T2, timeout_s)

function (r::LJHReaderFeb2017)()
  fname, analyzer, product_writer, endchannel = r.fname, r.analyzer, r.product_writer, r.endchannel
  file_exist = wait_for_file_to_exist(fname,30)
  if !file_exist
    r.status = :timeout
    return
  end
  ljh = LJH.LJHFile(fname)
  r.ljh = Nullable(ljh)
  write_header(product_writer, ljh)
  r.status = :running
  while true
    while true # read and process all data
      data=LJH.tryread(ljh)
      isnull(data) && break
      analysis_products = analyzer(get(data))
      product_writer(analysis_products)
    end
    isready(endchannel) && break
    watch_file(ljh,timeout_s)
  end
  close(ljh)
  r.status = :done
end

"Launch create and launch an LJHReaderFeb2017.
If `continuous` is true is will continue trying to read from `fname` until something does
`put!(reader.endchannel,true)`. If it `continuous` is false, it will stop as soon as it reads all data in the file."
function launch_reader(fname, analyzer, product_writer; continuous=true, timeout_s=1)
  reader = LJHReaderFeb2017(fname, analyzer, product_writer, timeout_s)
  !continuous && put!(reader.endchannel,true)
  schedule(reader.task)
  reader
end

immutable MassCompatibleAnalysisFeb2017
  filter::Vector{Float64} # single lag filter
  filter_at::Vector{Float64} # single lag filter arrival time component
  npresamples::Int64 # number of sample trigger
  nsamples::Int64 # length of pulse in sample
  average_pulse_peak_index::Int64 # peak index of average pulse, look for postpeak_deriv after this
  frametime::Float64 # time between two samples in seconds
end
immutable MassCompatibleDataProductFeb2017
  filt_value        ::Float64
  arrival_time_indicator ::Float64
  timestamp_usec    ::Float64
  rowcount          ::Int64
  pretrig_mean      ::Float64
  pretrig_rms       ::Float64
  pulse_average     ::Float64
  pulse_rms         ::Float64
  rise_time         ::Float64
  postpeak_deriv    ::Float64
  peak_index        ::Int16
  peak_value        ::UInt16
  min_value         ::UInt16
end
function (a::MassCompatibleAnalysisFeb2017)(record::LJH.LJHRecord)
  summary = summarize(record.data, a.npresamples,a.nsamples, a.average_pulse_peak_index, a.frametime)
  filt_value, arrival_time_indicator = filter_single_lag(record.data, a.filter, a.filter_at, pretrig_mean, npresamples, shift_threshold)
  MassCompatibleDataProductFeb2017(filt_value, arrival_time_indicator, record.timestamp_usec, record.rowcounts,
  summary.pretrig_mean, summary.pretrig_rms, summary.pulse_average, summary.pulse_rms, summmary.rise_time,
  summary.postpeak_deriv, summary.peak_index, summary.min_value )
end

immutable DataWriter
  f::IOStream
end
write(dw::DataWriter,x...) = write(dw.f,x...)
function (dw::DataWriter)(d::MassCompatibleDataProductFeb2017)
  write(dw,d)
end
Base.close(dw::DataWriter) = close(dw.f)
function write_header(dw::DataWriter,f::LJH.LJHFile)
  # dump(dw.f,Pope.MassCompatibleDataProductFeb2017)
  # write(dw, "from file: $f.filename\n")
  # write(dw,"HEADER DONE\n")
end

"wait_for_file_to_exist(fname, timeout_s = 30)
If the file still doesn't exist after `timeout_s` return `false`. Otherwise return `true` once the file exists."
function wait_for_file_to_exist(fname, timeout_s = 30)
  sleeptime = 0.050
  maxsleeptime = 10.0
  totalslept = 0.0
  while true
    isfile(fname) && return true
    totalslept >= timeout_s && return false
    sleep(sleeptime)
    totalslept+=sleeptime
    sleeptime = min(timeout_s-totalslept, sleeptime*2)
  end
end

end # module
