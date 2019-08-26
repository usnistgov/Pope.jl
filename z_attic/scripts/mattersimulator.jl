#!/usr/bin/env julia
using DocOpt, Pope

doc = """
Matter Simulator (aka LJH Rewriter)
Usage:
  mattersimulator.jl <ljhpath> [<output>]
  mattersimulator.jl [--maxchannels=4] [--timeout=0] [--fastforward=3.2] <ljhpath> [<output>]
  mattersimulator.jl <ljhpath> [<output>]
  mattersimulator.jl -h | --help

Options:
  --maxchannels=<mc>   Maximum number of channels to re-write. [default: 240].
  --timeout=<to>       Maximum time (in seconds) to wait between writing successive pulses. Will not maintain synchronization between channels. [default: 0.01]
  --fastforward=<ff>   Reduce the delays between pulses by this factor. Use with large timeout to replay fast, but with synchronization. [default: 1.0]

Help exposition:
  Where <ljhpath> points to a single ljh file, and <output> points directory in which to re-write the ljh files.
  Matter Simulator will find other channels of the same ljh group, and include up to <mc> of them. Then it will start
  to write to new ljh files in directory <output> (created if neccesary). The new ljh files will eventually be identical to the
  input ljh files. However, the pulse records will be written at appoximatley the same rate as they were origninally, based on the
  timestamps in the original ljh files. Reduce <to> to make the new files be written faster.

  Matter simualator will update the sentinel file (in ~/.daq) when it starts and finishes writing.

  If output is not passed, a random temporary directory will be used.

  If you have succesfully run `Pkg.test("Pope") from within Julia, this should work:
  ./mattersimulator.jl ~/.julia/v0.6/ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh
"""

arguments = docopt(doc, version=v"0.0.1")
maxchannels = parse(Int,arguments["--maxchannels"])
timeout_s = parse(Float64,arguments["--timeout"])
fastforward = parse(Float64,arguments["--fastforward"])
ljhpath = expanduser(arguments["<ljhpath>"])
output = arguments["<output>"]
if output == nothing
  output = joinpath(tempdir(), randstring(8))
else
  output = expanduser(output)
end

ulimit() = a=parse(Int,readstring(`bash -c "ulimit -n"`))
if ulimit() <= 500
  println("WARNING: open file limit too low, run `ulimit -n 1000` before opening julia")
  exist()
end

Pope.mattersim(ljhpath, output, timeout_s, fastforward, maxchannels)
