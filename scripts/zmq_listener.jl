#!/usr/bin/env julia
using Pope, ZMQ, DocOpt

doc = """
zmq_listener
Provide <lo> and <hi> in eV, and point to a <calfile> that has filt_value to energy calibrations.
Usage:
  zmq_listener.jl <lo> <hi> <calfile>

Options:

"""


arguments = docopt(doc, version=v"0.0.1")
preknowledge_filename = expanduser(arguments["<preknowledge>"])
ljhpath = expanduser(arguments["<ljhpath>"])
output_filename = expanduser(arguments["<output>"])
sub_socket = ZMQ.Socket(Pope.ZMQDataSinkConsts.context, ZMQ.SUB)
ZMQ.subscribe(sub_socket)
ZMQ.connect(sub_socket, "tcp://localhost:$(Pope.ZMQ_PORT)")
function recv_multipart(socket)
  out = ZMQ.Message[]
  push!(out, recv(socket))
  while ZMQ.ismore(socket)
    push!(out, recv(socket))
  end
  out
end
recv_dataproduct(socket) = make_dataproduct(recv_multipart(socket))
function make_dataproduct(out)
  channel_string = takebuf_string(convert(IOStream, out[1]))
  channel_number = parse(Int, channel_string)
  dp = read(seekstart(convert(IOStream,out[2])),Pope.MassCompatibleDataProductFeb2017,1)[1]
  return channel_string, channel_number, dp
end
isheader(out) = startswith(unsafe_string(out[1]),"header")
type ROI
  name::String
  lo::Float64
  hi::Float64
  count::Int
end
inroi(roi::ROI, v) = ROI.lo <= v <= ROI.hi
push!(roi::ROI, v) = (roi.count+=inroi(roi,v))
reportcounts(roi::ROI) = (println("$(roi.name) $(roi.counts)");roi.counts=0)
roi = ROI("test ROI",5000,10000,0)

"stand in for actual calibration"
applycal(filt_value::Float64,channel_number::Int) = filt_value

endchannel = Channel{Bool}(1)

@schedule while !isready(endchannel)
  out = recv_multipart(socket)
  isheader(out) && continue
  channel_string, channel_number, dp = make_dataproduct(out)
  energy = applycal(filt_value, channel_number)
  push!(roi,energy)
end

@schedule while true
  sleep(1)
  reportcounts(roi)
end
