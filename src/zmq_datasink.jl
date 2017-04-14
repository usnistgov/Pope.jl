# fixes for ZMQ
function  Base.setindex!(a::Message, v, i::Integer)
    if i < 1 || i > length(a)
        throw(BoundsError())
    end
    unsafe_store!(pointer(a), v, i)
end
# use this to make small messages fast
function message(s)
  b = IOBuffer()
  write(b,s)
  m = Message(b.size)
  m[:]=b.data
  m
end

function sendfast(socket::Socket, zmsg::Message, SNDMORE::Bool=false)
  while true
      rc = ccall((:zmq_msg_send, ZMQ.zmq), Cint, (Ptr{Message}, Ptr{Void}, Cint),
                  &zmsg, socket.data, (ZMQ.ZMQ_SNDMORE*SNDMORE) | ZMQ.ZMQ_DONTWAIT)
      if rc == -1
          ZMQ.zmq_errno() == EAGAIN || throw(ZMQ.StateError(ZMQ.jl_zmq_error_str()))
          while (get_events(socket) & POLLOUT) == 0
              wait(socket)
          end
      else
          #get_events(socket) != 0 && notify(socket)
          notify(socket)
          break
      end
  end
end


immutable ZMQDataSink
  s::ZMQ.Socket
  channel_number::Int
end
function Base.write(zds::ZMQDataSink, dp)
  send_multipart(zds.s, [message("$(zds.channel_number)"), message(dp)])
end
function send_multipart(socket::Socket, parts::Vector{Message})
  for msg in parts[1:end-1]
   sendfast(socket, msg, SNDMORE)
  end
  return sendfast(socket, parts[end])
end
function write_header(zds::ZMQDataSink, ljh, analyzer)
  send_multipart(zds.s,message.(["header$(zds.channel_number)","write_header called"]))
end
function write_header_end(zds::ZMQDataSink, ljh, analyzer)
  send_multipart(zds.s,message.(["header$(zds.channel_number)","write_header_end called"]))
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
  "init_for_zmqdatasink(portin::Int;verbose=false, error_on_already_initialized=false)"
  function init_for_zmqdatasink(portin::Int;verbose=false, error_on_already_initialized=false)
    if initialized && error_on_already_initialized
      error("ZMQDataSinkConsts already initialized")
    elseif initialized
      return nothing
    end
    global port = portin
    global context = ZMQ.Context()
    global socket = ZMQ.Socket(context, ZMQ.PUB)
    ZMQ.bind(socket, "tcp://*:$port")
    global initialized = true
    verbose && println("Pope initialized ZMQ publisher on port $port")
    return nothing
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

"make_buffered_hdf5_and_zmq_multi_sink(output_file, channel_number)
makes a BufferedHDF5Writer and a ZMQDataSink, for the same channel,
puts them both into a MultipleDataSink."
function make_buffered_hdf5_and_zmq_multisink(output_file, channel_number)
  product_writer_a = Pope.make_buffered_hdf5_writer(output_file, channel_number)
  product_writer_b = Pope.make_zmqdatasink(channel_number)
  Pope.MultipleDataSink(product_writer_a,product_writer_b)
end
