"asbstract DataSink
subtype `T` must have methods:
`write(ds::T, dp::S)` where `S` is a subtype of DataProduct
`write_header(ds, ljh, analyzer)` where ljh is an LJHFile, and analyzer is a MassCompatibleAnalysisFeb2017
`write_header_end(ds,ljh,analyzer)` which amends the header after all writing is finalized
for things like number of records that are only known after all writing
`close(ds)`"
immutable ZMQDataSink
  s::ZMQ.Socket
  channel_number::Int
end
function Base.write(zds::ZMQDataSink, x...)
  b=IOBuffer()
  write(b,x...)
  send_multipart(zds.s, ["$(zds.channel_number)", Message(b)])
end
function send_multipart(socket::Socket, parts::Array)
  for msg in parts[1:end-1]
   send(socket, msg, SNDMORE)
  end
  return send(socket, parts[end])
end
function write_header(zds::ZMQDataSink, ljh, analyzer)
  send_multipart(zds.s["header$(zds.channel_number)","write_header called"])
end
function write_header_end(zds::ZMQDataSink, ljh, analyzer)
  send_multipart(zds.s,["header$(zds.channel_number)","write_header_end called"])
end
function Base.close(zds::ZMQDataSink)
  # for now don't actually close the socket in case, since there is no mechanism
  # to reopen it
  # closing the same ZMQ socket multiple times does not error or hang
end



module ZMQDataSinkConsts
using ZMQ
initialized = false
context = nothing
socket = nothing
port = nothing
  function init_for_zmqdatasink(portin::Int)
    if initialized
      error("ZMQDataSinkConsts already initialized")
    end
    global port = portin
    global context = ZMQ.Context()
    global socket = ZMQ.Socket(context, ZMQ.PUB)
    ZMQ.bind(socket, "tcp://*:$port")
    global initialized = true
  end
end
const init_for_zmqdatasink = ZMQDataSinkConsts.init_for_zmqdatasink

"make_zmqdatasink(channel::Int)
must call `init_for_zmqdatasink(port)` first
Returns a ZMQDataSink for `channel`"
function make_zmqdatasink(channel::Int)
  ZMQDataSinkConsts.initialized || error("must call init_for_zmqdatasink(port) first")
  ZMQDataSink(ZMQDataSinkConsts.socket,channel)
end
