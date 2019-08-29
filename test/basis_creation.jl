using Pope.NoiseAnalysis
using ARMA
using HDF5
using Random
import ReferenceMicrocalFiles
using Pope
using Test

# generate some fake data to make a basis from
x=1:400
npulses = 3000
data = zeros(Float64,length(x),npulses)
# components
a=x[:]
b=20*(sinpi.(x/10) .+ 1)
c=10*(cospi.(x/10) .+ 1)
Random.seed!(0)
for i in 1:size(data,2)
    data[:,i] .+= a .* rand(1:10)
    data[:,i] .+= b .* rand(1:10)
    data[:,i] .+= c .* rand(1:10)
end
# data=round.(data)

model = ARMA.ARMAModel([2.41644, -4.25252, 1.85175], [1, -1.90467, .905899])
covar = ARMA.model_covariance(model, length(x))

noise_result = NoiseResult(ARMA.model_covariance(model, length(x)),
    ARMA.model_psd(model, length(x)),0,0,"",model)
frac_keep = 0.8
n_loop = 5
n_pulses_for_train=npulses
n_basis = 3
n_presamples = 0
tsvd_method_string="TSVD"
pulse_file = "dummy filename"
tsvd_basis, tsvd_basisinfo = Pope.create_basis_one_channel(data,noise_result,
    frac_keep, n_loop,
    n_pulses_for_train, n_basis,tsvd_method_string, n_presamples,
    pulse_file,-1)

h5open("artifacts/dummy_model.h5","w") do h5 Pope.hdf5save(h5,tsvd_basisinfo) end
loaded_basisinfo = h5open("artifacts/dummy_model.h5","r") do h5 Pope.hdf5load(Pope.SVDBasisWithCreationInfo,h5) end
loaded_basis = h5open("artifacts/dummy_model.h5","r") do h5 Pope.analyzer_from_preknowledge(h5) end

@testset "TSVD basis" begin
    @test tsvd_basisinfo.pulse_file == pulse_file
    @test loaded_basisinfo.svdbasis.basis==loaded_basis.basis==tsvd_basisinfo.svdbasis.basis
end

rmfdir = splitdir(pathof(ReferenceMicrocalFiles))[1]
noisepath = normpath("$(rmfdir)/../ljh/20150707_C_chan13.noi")
ljhpath = normpath("$(rmfdir)/../ljh/20150707_D_chan13.ljh")
noise_result_path = "artifacts/noise_result.h5"
model_path = "artifacts/model.h5"

# take a constant, arrival time, and average pulse from data
# train on residuals

tsvd_method_string="TSVDmass3"
pulse_file = "dummy filename"
n_basis=3 # test the case where the only 3 elements return are the mass3 (dc value, average pulse, pulse derivative)
mass3_basis, mass3_basisinfo = Pope.create_basis_one_channel(data,noise_result,
    frac_keep, n_loop,
    n_pulses_for_train, n_basis,tsvd_method_string, n_presamples,
    pulse_file,-1)

n_basis=5
mass3_basis, mass3_basisinfo = Pope.create_basis_one_channel(data,noise_result,
    frac_keep, n_loop,
    n_pulses_for_train, n_basis,tsvd_method_string, n_presamples,
    pulse_file,-1)

if !haskey(ENV,"POPE_NOMATPLOTLIB")
    @testset "scripts with SVDBasis" begin
        @test success(run(`julia ../scripts/noise_analysis.jl $noisepath -o $noise_result_path`))
        @test success(run(`julia ../scripts/basis_create.jl $ljhpath $noise_result_path -o $model_path`))
        @test success(run(`julia ../scripts/basis_plots.jl $model_path`))
        @test success(run(`julia ../scripts/noise_plots.jl $noise_result_path`))
    end
end
