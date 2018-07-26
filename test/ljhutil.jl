using Pope.LJH

@testset "ljhutil" begin
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

    localdirljhpath = "20150707_D_chan13.ljh"
    a,b,c = LJH.dir_base_ext(localdirljhpath)
    @test a=="."
    @test b=="20150707_D"
    @test c==".ljh"

dir = "artifacts/ljh_test1"
isdir(dir) || mkdir(dir)
fnames = LJH.fnames(joinpath(dir,"ljh_test1"),1:2:480)
for fname in fnames
    touch(fname)
end
ljhdict = LJH.allchannels(first(fnames))
ljhdict2 = LJH.allchannels(dir)
@test ljhdict == ljhdict2
@test collect(keys(ljhdict))==collect(1:2:480)
@test collect(values(ljhdict))==fnames

dir_noi = "artifacts/ljh_test2"
isdir(dir_noi) || mkdir(dir_noi)
fnames_noi = LJH.fnames(joinpath(dir_noi,"ljh_test2.noi"),1:2:480)
for fname in fnames_noi
    touch(fname)
end
ljhdict_noi = LJH.allchannels(first(fnames_noi))
@test collect(keys(ljhdict_noi))==collect(1:2:480)
@test collect(values(ljhdict_noi))==fnames_noi
@test ljhdict_noi != ljhdict

outputname(x) = Pope.outputname(x,"annotation")
@test outputname("abc_chan1.ljh") == outputname("abc_chan1.noi") == outputname("abc")
@test Pope.outputname("abc_chan1.ljh","model") == "./abc_model.hdf5"
@test Pope.outputname("abc_chan1.ljh","model","pdf") == "./abc_model.pdf"
@test Pope.outputname("abc_chan1.ljh","model",".pdf") == "./abc_model.pdf"
end
