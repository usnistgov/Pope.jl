#!/usr/bin/env julia
using DocOpt, HDF5
using Pope: LJHUtil

doc = """
Pope (Pass one pulse examiner)
Usage:
  popewatchesmatter.jl <preknowledge>
  popewatchesmatter.jl -h | --help

Options:
Help exposition:
  Looks at $(LJHUtil.sentinel_file_path) to determine ljh path to analyze. Starts analyzing the next file to be written by matter.
  <preknowledge> points to a valid HDF5 file in the pope preknowledge format.
  Output filename will be determined by a call to `Pope.LJHUtil.hdf5_name_from_ljh(ljhfilename)`
  If this file doesn't exist yet you can use `Pope.LJHUtil.write_sentinel_file("fake.ljh",true)` to create it.
"""

arguments = docopt(doc, version=v"0.0.1")
preknowledge_filename = expanduser(arguments["<preknowledge>"])

while true
  ljhpath, writingbool = wait_for_writing_status(true)
  println("Matter has started writing $ljhpath, starting POPE")
  pkfile = get_preknowledge_file(preknowledge_filename)
  output_file = get_output_file(ljhpath)
  readers = launch_continuous_analysis(pkfile, ljhpath, output_file)
  ljhpath, writingbool = wait_for_writing_status(false)
  println("Matter has stopped writing $ljhpath, finishing POPE")
  sleep(3) # give some time for ljh files to be finalized
  finish_analysis(readers)
end

function get_preknowledge_file(preknowledge_filename)
  if ishdf5(preknowledge_filename)
    pkfile = h5open(preknowledge_filename,"r")
  else
    println("ERROR: $preknowledge_filename is not an hdf5 file")
    exit()
  end
end

function get_output_file(ljhpath)
  output_filename = Pope.LJHUtil.hdf5_name_from_ljh(ljhpath)
  println("output filename: $output_filename")
  if !isfile(output_filename) || arguments["--overwriteoutput"]
    output_file = h5open(output_filename,"w")
    return output_file
  else
    println("ERROR: $output_filename already exists, cannot use it as output file")
    exit()
  end
end

function wait_for_writing_status(status)
  println("waiting for matter writing status = $status")
  while true
    ljhpath, writingbool = LJHUtil.matter_writing_status()
    if writingbool == status
      return ljhpath, writingbool
    end
    watch_file(LJHUtil.sentinel_file_path)
  end
end

function launch_continuous_analysis(pkfile, ljhpath, output_file)
  println("starting Pope analysis:")
  @show ljhpath
  @show pkfile.filename
  @show output_filename
  println("")
  readers = []
  for name in names(pkfile)
    channel_number = parse(Int,name[5:end])
    ljh_filename = Pope.LJHUtil.fnames(ljhpath,channel_number)
    # if !isfile(ljh_filename)
    #   println("Channel $channel_number: exists in preknowledge file, but ljh does not exist")
    #   continue
    # end
    analyzer = try
      analyzer = Pope.analyzer_from_preknowledge(pkfile[name])
    catch
      println("Channel $channel_number: failed to generate analyzer from preknowledge file")
      continue
    end
    println("Channel $channel_number: starting analysis")
    product_writer = Pope.make_buffered_hdf5_writer(output_file, channel_number)
    reader = Pope.launch_reader(ljh_filename, analyzer, product_writer;continuous=true)
    push!(readers, reader)
  end
end

function finish_analysis(readers)
  Pope.stop.(readers)
  wait.(readers)
end
