using Pope: LJH
using Base.Test
using ReferenceMicrocalFiles



@testset "matter simulator" begin

src = ReferenceMicrocalFiles.dict["good_mnka_mystery"].filename
dest = tempdir()
timeout_s=0.0001
maxchannels = 4
fastforward = 1

sim = @schedule Pope.mattersim(src, dest, timeout_s, fastforward, maxchannels)
sleep(0.1)
filename0, writingbool0 = LJH.matter_writing_status()
wait(sim)
filename1, writingbool1 = LJH.matter_writing_status()

@test writingbool0
@test !writingbool1
@test filename0==filename1
f0 = open(filename0,"r")
f1 = open(filename1,"r")
@test read(f0)==read(f1)
close(f0)
close(f1)
end
