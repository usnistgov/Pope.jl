using Base.Test

@testset "scripts" begin

noisepath = joinpath(Pkg.dir(),"ReferenceMicrocalFiles/ljh/20150707_C_chan13.noi")
ljhpath = joinpath(Pkg.dir(),"ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh")
preknowledgepath = joinpath(@__DIR__,"artifacts","pk_1x32_3072samples.preknowledge")

@test nothing==run(`julia ../scripts/benchmark.jl --runtime_s=3`)
@test nothing==run(`julia ../scripts/mattersimulator.jl --timeout=0 $ljhpath`)

# this section of the testing relies on python and mass
# I haven't set up mass on travis, so for now I will make the python optional
# make preknowledge will exit with a printed warning if mass is not available
# outputs needed by further testing are stored in artifacts
# artifacts/pk_1x32_3072samples.preknowledge
# artifacts/make_preknowledge_temp.hdf5
@test nothing==run(`python ../scripts/make_preknowledge.py $ljhpath $noisepath artifacts --apply_filters --noprompt --quality_report --dont_popeonceafter --temp_out_dir=artifacts --overwriteoutput`)
@test nothing==run(`julia ../scripts/popeonce.jl --overwriteoutput $ljhpath $preknowledgepath artifacts/output.h5`)

end #testset
