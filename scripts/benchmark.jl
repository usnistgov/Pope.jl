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
using ProgressMeter
using Pope: LJH, LJHUtil
using HDF5
import Distributions.Exponential

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
dname,endchannel,ljhmadechannel,s=LJH.launch_writer_other_process(d=d,dt=frametime,channels=channels,npre=npresamples,data=data, dname=dname)
wait(ljhmadechannel) # makes sure all the LJH files are created before moving on
println("Writing in progress")


nozmq || Pope.init_for_zmqdatasink(Pope.ZMQ_PORT,verbose=true)
println("Starting analyzing")
h5 = h5open(outputname,"w", "libver_bounds", (HDF5.H5F_LIBVER_LATEST, HDF5.H5F_LIBVER_LATEST))
readers_vec = []
fname=""
for channel in channels
  fname = LJHUtil.fnames(dname, channel)
  analyzer = Pope.MassCompatibleAnalysisFeb2017(filter_values, filter_at, npresamples, nsamples, average_pulse_peak_index, frametime, shift_threshold, pretrigger_rms_cuts, postpeak_deriv_cuts, analyzer_pk_string)
  if nozmq
    product_writer = Pope.make_buffered_hdf5_writer(h5, channel)
  else
    product_writer = Pope.make_buffered_hdf5_and_zmq_multisink(h5, channel)
  end
  reader = Pope.make_reader(fname, analyzer, product_writer;continuous=true)
  push!(readers_vec, reader)
end
readers = Pope.Readers(readers_vec)
Pope.write_headers(readers)
schedule.(readers)
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
