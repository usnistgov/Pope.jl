using Base.Test

@testset "scripts" begin

noisepath = joinpath(Pkg.dir(),"ReferenceMicrocalFiles/ljh/20150707_C_chan13.noi")
ljhpath = joinpath(Pkg.dir(),"ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh")
preknowledgepath = joinpath(Pkg.dir(),"Pope/test/pk_1x32_3072samples.preknowledge")

@test nothing==run(`julia ../scripts/benchmark.jl --runtime_s=3`)
@test nothing==run(`julia ../scripts/mattersimulator.jl --timeout=0 $ljhpath`)
@test nothing==run(`python ../scripts/make_preknowledge.py $ljhpath $noisepath --apply_filters --noprompt --quality_report --dont_popeonceafter`)
@test nothing==run(`julia ../scripts/popeonce.jl --overwriteoutput $ljhpath $preknowledgepath output.h5`)

end #testset
