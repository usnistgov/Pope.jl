using Base.Test

@testset "scripts" begin

noisepath = joinpath(Pkg.dir(),"ReferenceMicrocalFiles/ljh/20150707_C_chan13.noi")
ljhpath = joinpath(Pkg.dir(),"ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh")
preknowledgepath = joinpath(@__DIR__,"artifacts","pk_1x32_3072samples.preknowledge")

@test nothing==run(`julia ../scripts/benchmark.jl --runtime_s=3`)
@test nothing==run(`julia ../scripts/mattersimulator.jl --timeout=0 $ljhpath`)

# make_preknowledge python and mass
# if the enviroment variable POPE_NOMASS exists
# we skip make_preknowledge and instead copy required files
# from ReferenceMicrocalFiles
if !haskey(ENV,"POPE_NOMASS")
    @test nothing==run(`python ../scripts/make_preknowledge.py $ljhpath $noisepath artifacts --apply_filters --noprompt --quality_report --dont_popeonceafter --temp_out_dir=artifacts`)
else
    srcdir = joinpath(Pkg.dir(),"ReferenceMicrocalFiles","artifacts")
    cp(joinpath(srcdir,last(splitdir(preknowledgepath))), preknowledgepath)
    cp(joinpath(srcdir,"make_preknowledge_temp.hdf5"), joinpath("artifacts","make_preknowledge_temp.hdf5"))
    touch("artifacts/nomass") # add marker to indicate tests were run with nomass
end
@test nothing==run(`julia ../scripts/popeonce.jl $ljhpath $preknowledgepath artifacts/output.h5`)

end #testset
