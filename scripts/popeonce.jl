#!/usr/bin/env julia
using DocOpt, HDF5

doc = """
Pope (Pass one pulse examiner)
Usage:
  popeonce.jl <ljhpath> <preknowledge> <output>
  popeonce.jl --overwriteoutput <ljhpath> <preknowledge> <output>
  popeonce.jl -h | --help

Options:
  --overwriteoutput   Overwrite the output file if it already exists.
Help exposition:
  Where <ljhpath> points to a single ljh file, and <preknowledge> points to a valid HDF5 file in the pope preknowledge format. <output> points to a location where the output hdf5 file will be written.

  If you have succesfully run `Pkg.test("Pope")` from within Julia, this should work:
  popeonce.jl --overwriteoutput ~/.julia/v0.5/ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh ~/.julia/v0.5/Pope/test/preknowledge.h5 output.h5
"""


arguments = docopt(doc, version=v"0.0.1")
preknowledge_filename = expanduser(arguments["<preknowledge>"])
ljhpath = expanduser(arguments["<ljhpath>"])
output_filename = expanduser(arguments["<output>"])


using Pope

pkfile = h5open(preknowledge_filename,"r")
if !isfile(output_filename) || arguments["--overwriteoutput"]
  output_file = h5open(output_filename,"w")
else
  println("ERROR: $output_filename already exists, cannot use it as output file")
  exit()
end

println("starting Pope analysis:")
@show ljhpath
@show preknowledge_filename
@show output_filename
println("")

for name in names(pkfile)
  channel_number = parse(Int,name[5:end])
  ljh_filename = Pope.LJHUtil.fnames(ljhpath,channel_number)
  if !isfile(ljh_filename)
    println("Channel $channel_number: exists in preknowledge file, but ljh does not exist")
    continue
  end
  analyzer = try
    analyzer = Pope.analyzer_from_preknowledge(pkfile[name])
  catch
    println("Channel $channel_number: failed to generate analyzer from preknowledge file")
    continue
  end
  println("Channel $channel_number: starting analysis")
  product_writer = Pope.make_buffered_hdf5_writer(output_file, channel_number)
  reader = Pope.launch_reader(ljh_filename, analyzer, product_writer;continuous=false)
  wait(reader.task)
  println("Channel $channel_number: finished analysis, status = $(reader.status)")
end

println("done")