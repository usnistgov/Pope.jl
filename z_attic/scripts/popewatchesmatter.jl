#!/usr/bin/env julia
using DocOpt, HDF5, DataStructures, ZMQ
using Pope: LJH

doc = """
Pope (Pass one pulse examiner)
Usage:
  popewatchesmatter.jl <preknowledge>
  popewatchesmatter.jl [--overwriteoutput] [--forcenowrite] <preknowledge>
  popewatchesmatter.jl -h | --help

Options:
Help exposition:
  --overwriteoutput    Use this flag to allow popewatchesmatter to overwrite existing output files.(mostly for testing)
  --forcenowrite       Use this flag to change the matter writing status to `\"forced\"`,`false` before checking the writing status. (testing only)

  Looks at $(LJH.sentinel_file_path) to determine ljh path to analyze. Starts analyzing the next file to be written by matter.
  <preknowledge> points to a valid HDF5 file in the pope preknowledge format.
  Output filename will be determined by a call to `Pope.outputname`
  If this file doesn't exist yet you can use `LJH.write_sentinel_file("fake.ljh",true)` to create it.
"""

arguments = docopt(doc, version=v"0.0.1")
preknowledge_filename = expanduser(arguments["<preknowledge>"])

"zmq_reporter(port,message,rep_period_s,endchannel=Channel{Bool}(1))
Create a ZMQ Pub socket on `port` that sends `message` every `rep_period_s` until `isready(endchannel).`
Used to report to monitory.py in nasa_daq."
function zmq_reporter(port,message,rep_period_s,endchannel=Channel{Bool}(1))
  ctx=Context()
  socket = Socket(ctx, ZMQ.PUB)
  ZMQ.connect(socket,"tcp://localhost:$port")
  while !isready(endchannel)
    sleep(rep_period_s)
    ZMQ.send(socket, Message(message))
  end
  ZMQ.close(socket)
end
@schedule zmq_reporter(Pope.MONITOR_PORT, "Pope watching", 2)

function get_preknowledge_file(preknowledge_filename)
  if ishdf5(preknowledge_filename)
    pkfile = h5open(preknowledge_filename,"r")
  else
    println("ERROR: $preknowledge_filename is not an hdf5 file")
    exit()
  end
end

function get_output_file(ljhpath)
  output_file = Pope.outputname(ljhpath,"pope")
  println("output filename: $output_file")
  if !isfile(output_file) || arguments["--overwriteoutput"]
    if !isdir(dirname(output_file))
      println("ERROR: $(dirname(output_file)) is not an existing directory, cannot create output file.")
      println("Did you delete the directory matter was writing to as it was writing? ")
      exit()
    end
    output_file = h5open(output_file,"w")
    return output_file
  else
    println("ERROR: $output_file already exists, cannot use it as output file")
    exit()
  end
end

function wait_for_writing_status(status)
  println("waiting for matter writing status = $status")
  while true
    ljhpath, writingbool = LJH.matter_writing_status()
    if writingbool == status
      return ljhpath, writingbool
    end
    watch_file(LJH.sentinel_file_path)
  end
end

function launch_continuous_analysis(preknowledge_filename, ljhpath, output_file)
  println("starting Pope analysis:")
  pkfile = get_preknowledge_file(preknowledge_filename)
  @show ljhpath
  @show pkfile.filename
  @show output_file
  println("")
  readers = Pope.Readers()
  for name in names(pkfile)
    channel_number = startswith(name,"chan") ? parse(Int,name[5:end]) : parse(Int,name) # handle chan1 or 1
    ljh_filename = LJH.fnames(ljhpath,channel_number)
    analyzer = try
      analyzer = Pope.analyzer_from_preknowledge(pkfile[name])
    catch
      println("Channel $channel_number: failed to generate analyzer from preknowledge file")
      continue
    end
    product_writer = Pope.make_buffered_hdf5_and_zmq_multisink(output_file,channel_number,analyzer)
    reader = Pope.make_reader(ljh_filename, analyzer, product_writer, progress_meter=false)
    push!(readers, reader)
  end
  close(pkfile)
  schedule(readers)
  println("Analysis started for $(length(readers)) channels.")
  monitor_endchannel = Channel{Bool}(1)
  @schedule zmq_reporter(Pope.MONITOR_PORT, "Pope analyzing", 2, monitor_endchannel)
  readers,monitor_endchannel
end

function finish_analysis(readers,monitor_endchannel)
  Pope.stop(readers)
  try
    wait(readers) # they should process all available data before wait returns
  catch ex
    println("WARNING: There were one or more errors in the reader tasks.")
    Base.show(ex)
  end
  isready(monitor_endchannel) && error("monitor_endchannel already ready")
  put!(monitor_endchannel,true)
end

function summarize_readers(readers)
  c = counter(collect(r.status for r in readers))
  println("Summary of channel analzyer statuses:")
  for (k,v) in c
    println("\t$v channels have status: $k")
  end
end

Pope.init_for_zmqdatasink(Pope.ZMQ_PORT,verbose=true)
println("popewatchesmatter on pid $(getpid())")
println("popewatchesmatter will run until interrupted, OR\nthe MATTER sentinel file points to a file called \"endpope\"")
function run()
  while true
    ljhpath0, writingbool = wait_for_writing_status(true)
    if ljhpath0 == "endpope" break end
    println("Matter has started writing $ljhpath0, starting POPE")
    output_file = get_output_file(ljhpath0)
    readers,monitor_endchannel = launch_continuous_analysis(preknowledge_filename, ljhpath0, output_file)
    ljhpath1, writingbool = wait_for_writing_status(false)
    if ljhpath0 != ljhpath1
      println("WARNING: ljhpath changed between open and close")
      println("writing status true: $ljhpath0")
      println("writing status false: $ljhpath1")
    end
    println("Matter has stopped writing $ljhpath0, waiting 3 seconds before Pope finishes analysis.")
    sleep(3) # give some time for ljh files to be finalized by matter
    finish_analysis(readers,monitor_endchannel)
    close(output_file)
    println("Pope finished analyzing $ljhpath0")
    summarize_readers(readers)
  end
end
if arguments["--forcenowrite"]
  LJH.write_sentinel_file("forced",false)
  println("Changed matter sentinel file to contain \"forced\", false.")
end
run()
println("popewatchesmatter finished.")
flush(STDOUT)
