using Pope: LJHUtil
using Base.Test
const WT = false # run @code_warntype

include("ljh.jl")

let
  data = zeros(UInt16,2000)
  npresamples = div(length(data),2)
  nsamples = length(data)
  frametime = 1e-6
  average_pulse_peak_index = 1200
  summary = Pope.summarize(data, npresamples, nsamples, average_pulse_peak_index, frametime)
  WT && @code_warntype Pope.summarize(data, npresamples, nsamples, average_pulse_peak_index, frametime)
  WT && @code_warntype Pope.estimate_rise_time(data, npresamples+1:summary.peak_index, summary.peak_value,summary.pretrig_mean,frametime)
  WT && @code_warntype Pope.max_timeseries_deriv_simple(data, summary.peak_index)
end

#name22 points to an LJH file after the ljh tests are run
ljh = LJH.LJHFile(name22)
filter=zeros(ljh.record_nsamples-1) # single lag filter
filter_at=zeros(ljh.record_nsamples-1) # single lag filter arrival time component
npresamples=ljh.pretrig_nsamples # number of sample trigger
nsamples=ljh.record_nsamples # length of pulse in sample
average_pulse_peak_index=ljh.pretrig_nsamples+30 # peak index of average pulse, look for postpeak_deriv after this
shift_threshold = 5
analyzer = Pope.MassCompatibleAnalysisFeb2017(filter, filter_at, npresamples, nsamples, average_pulse_peak_index, ljh.frametime, shift_threshold)
output_fname = tempname()
output_f = open(output_fname,"w")
@show stat(output_f)
product_writer = Pope.DataWriter(output_f)
reader = Pope.launch_reader(ljh.filename, analyzer, product_writer;continuous=false)
try
  wait(reader.task)
catch ex
  Base.show_backtrace(STDOUT,reader.task.backtrace)
  throw(ex)
end
@test reader.status == :done



f=open(output_fname,"r")
@show stat(f), position(f)
@show output_fname
@show d=read(f,sizeof(Pope.MassCompatibleDataProductFeb2017))
@show d2 = reinterpret(Pope.MassCompatibleDataProductFeb2017, d)[1]
@show d3 = analyzer(ljh[1])
@test d2==d3
dump(product_writer)

tdir = tempdir()
ljhnames = LJHUtil.fnames(tdir,1:2:480)
@show tdir
