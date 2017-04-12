using Pope, ZMQ, Base.Test

zmq_test_port = 70777

# prep for listening to the ZMQDataSink
Pope.init_for_zmqdatasink(zmq_test_port)

sub_socket = ZMQ.Socket(Pope.ZMQDataSinkConsts.context, ZMQ.SUB)
ZMQ.subscribe(sub_socket)
ZMQ.connect(sub_socket, "tcp://localhost:$zmq_test_port")
function recv_multipart(socket)
  out = ZMQ.Message[]
  push!(out, recv(socket))
  while ZMQ.ismore(socket)
    push!(out, recv(socket))
  end
  out
end

zds = Pope.make_zmqdatasink(1)
dp = Pope.MassCompatibleDataProductFeb2017(1,2,3,4,5,6,7,8,9,10,11,12,13)
write(zds,dp)
out = recv_multipart(sub_socket)
@testset "zmq_datasink" begin
  @test repr(zds.channel_number) == takebuf_string(convert(IOStream, out[1]))
  dp_out = read(seekstart(convert(IOStream,out[2])),Pope.MassCompatibleDataProductFeb2017,1)[1]
  @test dp_out == dp
end
close(zds.s) # close the socket directly, close(zds) is currently a no-op
close(sub_socket)
