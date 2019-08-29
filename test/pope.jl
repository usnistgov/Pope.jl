using InteractiveUtils
using Pope

@testset "wait_for_file_to_exist" begin
  endchannel = Channel{Bool}(1)
  fname = tempname()
  @async begin sleep(1); touch(fname) end
  t1=@elapsed @test Pope.wait_for_file_to_exist(fname, endchannel)
  @test t1>0.5
  @async begin sleep(1); put!(endchannel, true) end
  t2=@elapsed @test !Pope.wait_for_file_to_exist(tempname(), endchannel)
  @test t2>0.5
  #check that it returns true immediatley if file exists even if endchannel is already ready
  t3 = @elapsed @test Pope.wait_for_file_to_exist(fname, endchannel)
  @test t3<0.1
end
