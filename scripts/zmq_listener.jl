#!/usr/bin/env julia
using Pope, ZMQ, DocOpt

doc = """
zmq_listener
Provide <lo> and <hi> in eV, and point to a <calfile> that has filt_value to energy calibrations.
This is a sketch of how a popepipe_zmq<->spec interface would work it is not functional
Usage:
  zmq_listener.jl <lo> <hi> <calfile>

Options:

"""
# This is a sketch of how a popepipe_zmq<->spec interface
# would work
# it is not functional

arguments = docopt(doc, version=v"0.0.1")
calfilename = expanduser(arguments["<calfile>"])
lo = parse(Float64,arguments["<lo>"])
hi = parse(Float64,arguments["<hi>"])

ctx=Context()
socket = ZMQ.Socket(ctx, ZMQ.SUB)
ZMQ.subscribe(socket)
ZMQ.connect(socket, "tcp://localhost:$(Pope.ZMQ_PORT)")
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
inroi(roi::ROI, v) = roi.lo <= v <= roi.hi
Base.push!(roi::ROI, v) = (roi.count+=inroi(roi,v))
reportcounts(roi::ROI) = (println("$(roi.name) $(roi.count)");roi.count=0)
roi1 = ROI("test ROI 5k to 10k",5000,10000,0)
roi2 = ROI("test ROI 0 to ∞",0,Inf,0)
roi3 = ROI("input ROI $lo to $hi",lo,hi,0)
rois = [roi1,roi2,roi3]

"stand in for actual calibration"
applycal(dp,channel_number::Int) = dp.filt_value

"stand in for actual cuts"
iscut(dp,channel_number) = false

endchannel = Channel{Bool}(1)

@schedule while !isready(endchannel)
  out = recv_multipart(socket)
  isheader(out) && continue
  channel_string, channel_number, dp = make_dataproduct(out)
  energy = applycal(dp, channel_number)
  iscut(dp,channel_number) && continue
  for roi in rois push!(roi,energy) end
end

@schedule while !isready(endchannel)
  sleep(1)
  reportcounts.(rois)
end

sleep(10)
