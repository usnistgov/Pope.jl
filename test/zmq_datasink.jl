using Pope, ZMQ, Base.Test


# prep for listening to the ZMQDataSink
Pope.init_for_zmqdatasink(Pope.ZMQ_PORT)

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
function recv_dataproduct(socket)
  out = recv_multipart(socket)
  channel_string = String(take!(convert(IOStream, out[1])))
  channel_number = parse(Int, channel_string)
  dp = read(seekstart(convert(IOStream,out[2])),Pope.MassCompatibleDataProductFeb2017,1)[1]
  return channel_string, channel_number, dp
end

zds = Pope.make_zmqdatasink(1)
dp = Pope.MassCompatibleDataProductFeb2017(1,2,3,4,5,6,7,8,9,10,11,12,13)
Pope.write_header(zds,nothing,nothing)
out_header = recv_multipart(sub_socket)
write(zds,dp)
channel_string, channel_number, dp_out = recv_dataproduct(sub_socket)
Pope.write_header_end(zds,nothing,nothing)
out_header_end = recv_multipart(sub_socket)

@testset "zmq_datasink" begin
  @test repr(zds.channel_number) == channel_string
  @test dp_out == dp
end


# test multiple sink
datasinks = Pope.MultipleDataSink((Pope.make_zmqdatasink(1),Pope.make_zmqdatasink(2)))
@testset "MultipleDataSink" begin
  write(datasinks, dp)
  channel_string1, channel_number1, dp_out1 = recv_dataproduct(sub_socket)
  channel_string2, channel_number2, dp_out2 = recv_dataproduct(sub_socket)
  @test channel_string1 == repr(datasinks.t[1].channel_number)
  @test channel_string2 == repr(datasinks.t[2].channel_number)
  @test dp_out1 == dp
  @test dp_out2 == dp
  Pope.write_header(datasinks, nothing, nothing)
  Pope.write_header_end(datasinks, nothing,nothing)
end

close(zds.s) # close the socket directly, close(zds) is currently a no-op
close(sub_socket)
