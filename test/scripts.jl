using Base.Test

@testset "scripts" begin

ljhpath = joinpath(Pkg.dir(),"ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh")
preknowledgepath = joinpath(Pkg.dir(),"Pope/test/preknowledge.h5")

@test nothing==run(`julia ../scripts/benchmark.jl --runtime_s=3`)
@test nothing==run(`julia ../scripts/mattersimulator.jl --timeout=0 $ljhpath`)
@test nothing==run(`julia ../scripts/popeonce.jl --overwriteoutput $ljhpath $preknowledgepath output.h5`)

end #testset
