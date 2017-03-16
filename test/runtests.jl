using Pope: LJH, LJHUtil, HDF5
using ReferenceMicrocalFiles
using Base.Test
const WT = false # run @code_warntype

include("ljh.jl")
include("matter_simulator.jl")

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

const preknowledge_filename = "preknowledge.h5"
const mass_filename = "mass.h5"

if !isfile(preknowledge_filename)
  run(`python mass_analyzer.py`)
end

pkfile = h5open(preknowledge_filename,"r")
analyzer = Pope.analyzer_from_preknowledge(pkfile["chan13"])
output_fname = tempname()
output_h5 = h5open(output_fname,"w")
product_writer = Pope.make_buffered_hdf5_writer(output_h5, 13)
reader = Pope.launch_reader(ReferenceMicrocalFiles.dict["good_mnka_mystery"].filename, analyzer, product_writer;continuous=false)
try
  wait(reader.task)
catch ex
  Base.show_backtrace(STDOUT,reader.task.backtrace)
  throw(ex)
end
@test reader.status == :done
output_h5
close(output_h5)
# @show product_writer.timestamp_usec

massfile = h5open(mass_filename,"r")
popefile = h5open(output_fname,"r")
names(popefile["chan13"])
names(massfile["chan13"])
for name in names(popefile["chan13"])
  a=popefile["chan13"][name][:]
  b=massfile["chan13"][name][:]
  if eltype(a)==UInt16 #avoid overflow errors in testing
    a=Int.(a)
  end
  if name == "peak_index"
    @test all(a-b.==1) # python is 0 based, julia 1 based
  elseif name in ["postpeak_deriv"]
    @test sum(abs(a-b)./abs(a+b) .< 1e-6)/length(a)>0.993
  elseif name in ["pretrig_rms","peak_value","filt_phase","postpeak_deriv"]
    # @show sum(abs(a-b)./abs(a+b) .< 5e-3)/length(a)
    # I looked at the most extreme different, where pope has RMS ~32, and mass has ~11
    # it was an early trigger by about 6 samples. I believe mass missed it due to the
    # pretrigger_ignore_samples value, but that Pope's behaivor is more desired
    @test sum(abs(a-b)./abs(a+b) .< 5e-3)/length(a) > 0.995
  elseif name in ["rise_time"]
    # @show sum(abs(a-b)./abs(a+b) .< 5e-2)/length(a)
    @test sum(abs(a-b)./abs(a+b) .< 5e-2)/length(a) > 0.995
  elseif name in ["pulse_average", "pulse_rms"]
    @test isapprox(a,b,rtol=1e-3)
  else
    @test isapprox(a,b,rtol=1e-4)
  end
end

close(massfile)
close(popefile)

println("Run python script to open Pope HDF5 file.")
run(`python mass_open_pope_hdf5.py $output_fname`)
