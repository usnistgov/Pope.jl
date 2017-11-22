using Pope

@testset "ljhutil" begin
    noipath = "ReferenceMicrocalFiles/ljh/20150707_C_chan13.noi"
    a,b,c=Pope.LJHUtil.ljhsplit(noipath)
    @test a=="ReferenceMicrocalFiles/ljh"
    @test b=="20150707_C"
    @test c==".noi"

    ljhpath = "ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh"
    a,b,c=Pope.LJHUtil.ljhsplit(ljhpath)
    @test a=="ReferenceMicrocalFiles/ljh"
    @test b=="20150707_D"
    @test c==".ljh"

    @test Pope.LJHUtil.channel(ljhpath)==13
    @test Pope.LJHUtil.channel(noipath)==13

    @test Pope.LJHUtil.fnames(ljhpath,[1,2,3,4])==["ReferenceMicrocalFiles/ljh/20150707_D_chan1.ljh", "ReferenceMicrocalFiles/ljh/20150707_D_chan2.ljh", "ReferenceMicrocalFiles/ljh/20150707_D_chan3.ljh", "ReferenceMicrocalFiles/ljh/20150707_D_chan4.ljh"]
end
