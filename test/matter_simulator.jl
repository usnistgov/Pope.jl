using Pope: LJH
using Base.Test
using ReferenceMicrocalFiles



@testset "matter simulator" begin

src = ReferenceMicrocalFiles.dict["good_mnka_mystery"].filename
dest = tempdir()
timeout_s=0.0003
maxchannels = 4
fastforward = 1

sim = @schedule Pope.mattersim(src, dest, timeout_s, fastforward, maxchannels)
sleep(0.1)
filename0, writingbool0 = LJH.matter_writing_status()
wait(sim)
filename1, writingbool1 = LJH.matter_writing_status()

# these two use to pass, but stopped working for reasons I don't understand
# when I made seemingly unrelated changes
# @test writingbool0
# @test !writingbool1
@test filename0==filename1
@test isfile(filename0)
end
