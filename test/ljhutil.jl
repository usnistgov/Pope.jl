using Pope.LJH

# @testset "ljhutil" begin
    noipath = "ReferenceMicrocalFiles/ljh/20150707_C_chan13.noi"
    a,b,c=LJH.dir_base_ext(noipath)
    @test a=="ReferenceMicrocalFiles/ljh"
    @test b=="20150707_C"
    @test c==".noi"

    ljhpath = "ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh"
    a,b,c=LJH.dir_base_ext(ljhpath)
    @test a=="ReferenceMicrocalFiles/ljh"
    @test b=="20150707_D"
    @test c==".ljh"

    @test LJH.channel(ljhpath)==13
    @test LJH.channel(noipath)==13

    @test LJH.fnames(ljhpath,[1,2,3,4])==["ReferenceMicrocalFiles/ljh/20150707_D_chan1.ljh", "ReferenceMicrocalFiles/ljh/20150707_D_chan2.ljh", "ReferenceMicrocalFiles/ljh/20150707_D_chan3.ljh", "ReferenceMicrocalFiles/ljh/20150707_D_chan4.ljh"]
# end
