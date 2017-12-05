@testset "wait_for_file_to_exist" begin
  endchannel = Channel{Bool}(1)
  fname = tempname()
  @schedule begin sleep(1); touch(fname) end
  t1=@elapsed @test Pope.wait_for_file_to_exist(fname, endchannel)
  @test t1>0.5
  @schedule begin sleep(1); put!(endchannel, true) end
  t2=@elapsed @test !Pope.wait_for_file_to_exist(tempname(), endchannel)
  @test t2>0.5
  #check that it returns true immediatley if file exists even if endchannel is already ready
  t3 = @elapsed@test Pope.wait_for_file_to_exist(fname, endchannel)
  @test t3<0.1
end
# optional code warntype check
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

@testset "single reader with DataWriter" begin
  #name22 points to an LJH file after the ljh tests are run
  ljh = LJH.LJHFile(name22)
  filter=zeros(ljh.record_nsamples-1) # single lag filter
  filter_at=zeros(ljh.record_nsamples-1) # single lag filter arrival time component
  npresamples=ljh.pretrig_nsamples # number of sample trigger
  nsamples=ljh.record_nsamples # length of pulse in sample
  average_pulse_peak_index=ljh.pretrig_nsamples+30 # peak index of average pulse, look for postpeak_deriv after this
  shift_threshold = 5
  analyzer = Pope.MassCompatibleAnalysisFeb2017(filter, filter_at, npresamples, nsamples, average_pulse_peak_index, ljh.frametime, shift_threshold,[0.0,0.0],[0.0,0.0],"manually made in runtests.jl")
  output_fname = tempname()
  output_f = open(output_fname,"w")
  @show stat(output_f)
  product_writer = Pope.DataWriter(output_f)
  reader = Pope.make_reader(ljh.filename, analyzer, product_writer)
  readers = push!(Pope.Readers(),reader)
  schedule(readers)
  Pope.stop(readers)
  wait(readers)
  @test reader.status == "done"
  f=open(output_fname,"r")
  d=read(f,sizeof(Pope.MassCompatibleDataProductFeb2017))
  d2 = reinterpret(Pope.MassCompatibleDataProductFeb2017, d)[1]
  d3 = analyzer(ljh[1])
  @test d2==d3
end #testset single reader with DataWriter





# clean out the artifacts directory
isdir("artifacts") && rm("artifacts",recursive=true)
mkdir("artifacts")
# create the following files
const mass_filename = joinpath(@__DIR__,"artifacts","make_preknowledge_temp.hdf5")
const pope_output_filename = joinpath(@__DIR__,"artifacts","output.h5")
# by running make_preknowledge and popeonce in "scripts.jl"
include("scripts.jl")

# compare the values in the mass output to the values in the pope output
massfile = h5open(mass_filename,"r")
popefile = h5open(pope_output_filename,"r")
names(popefile["chan13"])
names(massfile["chan13"])
for name in names(popefile["chan13"])
  if name in ["calculated_cuts"] # skip things that aren't per pulse quantities
    continue
  end
  # println(name)
  a=popefile["chan13"][name][:]
  b=massfile["chan13"][name][:]
  if eltype(a)==UInt16 #avoid overflow errors in testing
    a=Int.(a)
  end
  if name == "peak_index"
    @test all(a-b.==1) # python is 0 based, julia 1 based
  elseif name in ["postpeak_deriv"]
    @test sum(abs.(a-b)./abs.(a+b) .< 1e-6)/length(a)>0.993
  elseif name in ["pretrig_rms","peak_value","filt_phase","postpeak_deriv"]
    # @show sum(abs(a-b)./abs(a+b) .< 5e-3)/length(a)
    # I looked at the most extreme different, where pope has RMS ~32, and mass has ~11
    # it was an early trigger by about 6 samples. I believe mass missed it due to the
    # pretrigger_ignore_samples value, but that Pope's behaivor is more desired
    @test sum(abs.(a-b)./abs.(a+b) .< 5e-3)/length(a) > 0.995
  elseif name in ["rise_time"]
    # @show sum(abs(a-b)./abs(a+b) .< 5e-2)/length(a)
    @test sum(abs.(a-b)./abs.(a+b) .< 5e-2)/length(a) > 0.995
  elseif name in ["pulse_average", "pulse_rms"]
    @test isapprox(a,b,rtol=1e-3)
  else
    @test isapprox(a,b,rtol=1e-4)
  end
end

close(massfile)
close(popefile)

if !haskey(ENV,"POPE_NOMASS")
  println("Run python script to open Pope HDF5 file.")
  run(`python mass_open_pope_hdf5.py $pope_output_filename $(Pkg.dir())`)
end
