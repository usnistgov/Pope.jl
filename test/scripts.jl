using Base.Test

@testset "scripts" begin

@test nothing==run(`julia ../scripts/benchmark.jl --runtime_s=3`)
@test nothing==run(`julia ../scripts/mattersimulator.jl --timeout=0 ~/.julia/v0.5/ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh`)
@test nothing==run(`julia ../scripts/popeonce.jl --overwriteoutput ~/.julia/v0.5/ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh ~/.julia/v0.5/Pope/test/preknowledge.h5 output.h5`)

end #testset
