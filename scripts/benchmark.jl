#!/usr/bin/env julia
using DocOpt

doc = """
Pope Benhmark and Live Test
Usage:
  benchmark.jl
  benchmark.jl [--nsamples=<ns>] [--nchannels=<nc>] [--cps=<cps>] [--nozmq] [--runtime_s=<rt>]
  benchmark.jl -h | --help

Options:
  --nsamples=<ns>    Samples per pulse. [default: 1000]
  --nchannels=<nc>   Number of channels to read and write. [default: 240]
  --cps=<cps>        Average counts per second per channel. [default: 100]
  --runtime_s=<rt>   Run for roughly this long, in seconds. [default: 30]
  --nozmq            Include this flag to not use the ZMQ port feature.

Help exposition:
  Launch a 2nd process to write LJH files, using an exponential distribution to determine time between
  writing records. Use the 1st process to analyze those LJH files using Pope in realtime.

  If you have succesfully run `Pkg.test("Pope") from within Julia, this should work:
  ./benchmark.jl
"""

arguments = docopt(doc, version=v"0.0.1")
nsamples = parse(Int,arguments["--nsamples"])
nchannels = parse(Int,arguments["--nchannels"])
cps = parse(Float64,arguments["--cps"])
runtime_s = parse(Float64,arguments["--runtime_s"])
nozmq = arguments["--nozmq"]





println("Starting Pope livetest/benchmark.")
if nprocs() == 1
  addprocs(1)
  println("added 1 proc")
end


@everywhere begin
using ProgressMeter
using Pope: LJH, LJHUtil
using HDF5
using Distributions: Distribution, Exponential
"    gen_ljh_files(dt=9.6e-6, npre=200, nsamp=1000,channels=1:2:480,dname=tempdir(); version=\"2.2.0\")
generate ljhs files (1 per channel) in directory `dname`, with the specified parameters
return a Vector{LJHFile} of the created files, with both read and write intents"
function gen_ljh_files(dt=9.6e-6, npre=200, nsamp=1000,channels=1:2:480,dname=joinpath(tempdir(),randstring(12)); version="2.2.0")
  !isdir(dname) && mkdir(dname)
  basename = last(split(dname,'/'))
  ljhs = LJH.LJHFile[]
  for ch in channels
    fname = joinpath(dname, basename*"_chan$ch.ljh")
    ljh=LJH.create(fname,dt, npre, nsamp; version=version, channel=ch)
    push!(ljhs,ljh)
  end
  ljhs
end
function launch_stocastic_writer{T}(endchannel, ljh::LJH.LJHFile{LJH.LJH_22,T}, d::Distribution, data=zeros(UInt16,ljh.record_nsamples))
  @schedule begin
    i=0
    while !isready(endchannel)
      sleep(rand(d))
      write(ljh,data,i+=1,round(Int, 1e6*time()))
    end
    close(ljh)
  end
end

function launch_stocastic_writers(endchannel, ljhs::Vector{LJH.LJHFile}, d::Distribution, data)
  for ljh in ljhs
    launch_stocastic_writer(endchannel, ljh, d, data)
  end
end

ulimit() = a=parse(Int,readstring(`bash -c "ulimit -n"`))

"    launch_writer_other_process(;d=Exponential(0.01),data=zeros(UInt16,1000),dt=9.6e-6, npre=200, nsamp=length(data),channels=1:2:480,dname=joinpath(tempdir(),randstring(12)), version=\"2.2.0\")
Opens one LJH file per channel in `channels` and starts writing pulse records with `data`
"
function launch_writer_other_process(;d=Exponential(0.01),data=zeros(UInt16,1000),dt=9.6e-6, npre=200, nsamp=length(data),channels=1:2:480,dname=joinpath(tempdir(),randstring(12)), version="2.2.0")
  nprocs() >= 2 || error("nprocs needs to be 2 or greater, try starting julia with `julia -p 1`")
  ulimit() >= 50+length(channels) || error("open file limit too low, run `ulimit -n 1000` before opening julia")
  endchannel = RemoteChannel(1)
  ljhmadechannel = RemoteChannel(1)
  s=@spawn begin
    ljhs = gen_ljh_files(dt, npre, nsamp, channels, dname; version=version)
    localendchannel = Channel(1)
    launch_stocastic_writers(localendchannel, ljhs, d, data)
    put!(ljhmadechannel,true)
    @schedule begin
      # checking a RemoteChannel causes lots of CPU usage in both tasks, avoid checking it alot
      wait(endchannel)
      put!(localendchannel,true)
    end
    @show s
  end
  return dname, endchannel, ljhmadechannel, s
end
end #@everywhere
data = collect(UInt16(0):UInt16(nsamples-1))
filter_values = zeros(nsamples-1)
filter_at = zeros(nsamples-1)
npresamples = 200
average_pulse_peak_index = 250
shift_threshold = 5
pretrigger_rms_cuts = postpeak_deriv_cuts = [0.0,0.0]
analyzer_pk_string = "manually created in benchmark.jl"
channels = 1:2:2*nchannels
frametime = 9.6e-6
λ = 1/cps # mean time (seconds) between pulses
d = Exponential(λ)
dname = joinpath(tempdir(),randstring(12))
outputname = tempname()

println("reading/analyzing process pid $(getpid())")
wait(@spawn println("writing process pid (probably) $(getpid())"))
println("writing and analzing $(length(channels)) channels")
println("$(1/λ) counts per second per channel")
println("$(length(data)) samples per pulse, 2 bytes/sample")
println("output file (wrriten by 1st process) $outputname")
println("ljh files (written by 2nd process) in $dname")
println("check activity monitor or top for CPU/memory usage")
println("temporary files are probably delted after you reboot, but you may want to check on your platform")

println("Starting writing")
dname,endchannel,ljhmadechannel,s=launch_writer_other_process(d=d,dt=frametime,channels=channels,npre=npresamples,data=data, dname=dname)
wait(ljhmadechannel) # makes sure all the LJH files are created before moving on
println("Writing in progress")


nozmq || Pope.init_for_zmqdatasink(Pope.ZMQ_PORT,verbose=true)
println("Starting analyzing")
h5 = h5open(outputname,"w", "libver_bounds", (HDF5.H5F_LIBVER_LATEST, HDF5.H5F_LIBVER_LATEST))
readers = Pope.Readers()
fname=""
for channel in channels
  fname = LJHUtil.fnames(dname, channel)
  analyzer = Pope.MassCompatibleAnalysisFeb2017(filter_values, filter_at, npresamples, nsamples, average_pulse_peak_index, frametime, shift_threshold, pretrigger_rms_cuts, postpeak_deriv_cuts, analyzer_pk_string)
  if nozmq
    product_writer = Pope.make_buffered_hdf5_writer(h5, channel)
  else
    product_writer = Pope.make_buffered_hdf5_and_zmq_multisink(h5, channel)
  end
  reader = Pope.make_reader(fname, analyzer, product_writer)
  push!(readers, reader)
end
schedule(readers)
println("Analyzing in progress")
println("Analyzing for $runtime_s seconds")
wait(@schedule begin
  tstart = time()
  tdiff = time()-tstart
  runtime_ms = round(Int, 1000*runtime_s)
  p = Progress(runtime_ms,1,"livetest/benchmark: ")
  while tdiff<runtime_s
    update!(p,round(Int,1000*(tdiff)))
    sleep(min(1,tdiff))
    tdiff = time()-tstart
  end
  update!(p,runtime_ms)
  put!(endchannel,true)
  println("writing stopped") end);
sleep(3) # make sure ljh files are all fully written, I get errors without this
Pope.stop(readers)
wait(readers)
println("analyzing stopped")


function check_values(channel, h5)
  fname = LJHUtil.fnames(dname, channel)
  ljh = LJH.LJHFile(fname)
  # @assert 80<length(ljh)/runtime_s<120  # the efault value in launch_writer_other_process has 100 cps
  g = h5["chan$channel"]
  for name in names(g)
    if name == "calculated_cuts"
      continue
    end
    @assert length(g[name])==length(ljh)
  end
  @assert(read(g["rowcount"])==collect(1:length(ljh)))
end

println("sanity checking analysis output")
for channel in channels
  check_values(channel,h5)
end
