using Pope
using Base.Test
using ReferenceMicrocalFiles

src = ReferenceMicrocalFiles.dict["good_mnka_mystery"].filename
dest = tempdir()
timeout_s=0.01

Pope.timed_ljh_rewriter(src,dest*"/T.ljh",0.01)

sim = @schedule Pope.mattersim(src,dest,timeout_s)
sleep(0.1)
filename0, writingbool0 = Pope.LJHUtil.matter_writing_status()
wait(sim)
filename1, writingbool1 = Pope.LJHUtil.matter_writing_status()

@testset "matter simulator" begin
@test writingbool0
@test !writingbool1
@test filename0==filename1
end
