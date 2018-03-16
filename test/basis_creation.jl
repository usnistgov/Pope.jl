using Pope.NoiseAnalysis
using ARMA

# generate some fake data to make a basis from
x=1:400
npulses = 3000
data = zeros(Float32,length(x),npulses)
# components
a=x[:]
b=20*(sinpi.(x/10)+1)
c=10*(cospi.(x/10)+1)
srand(0)
for i in 1:size(data,2)
    data[:,i]+=a*rand(1:10)
    data[:,i]+=b*rand(1:10)
    data[:,i]+=c*rand(1:10)
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
tsvd_method_string="TSVD"
pulse_file = "dummy filename"
tsvd_basis, tsvd_basisinfo = Pope.create_basis_one_channel(data,noise_result,
    frac_keep, n_loop,
    n_pulses_for_train, n_basis,tsvd_method_string,
    pulse_file,-1)

@testset "TSVD basis" begin
    @test tsvd_basisinfo.pulse_file == pulse_file
end

noisepath = joinpath(Pkg.dir(),"ReferenceMicrocalFiles/ljh/20150707_C_chan13.noi")
ljhpath = joinpath(Pkg.dir(),"ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh")
noise_result_path = "artifacts/noise_result.h5"
model_path = "artifacts/model.h5"

@test nothing==run(`julia ../scripts/noise_analysis.jl $noisepath -o $noise_result_path`)
@test nothing==run(`julia ../scripts/basis_create.jl $ljhpath $noise_result_path -o $model_path`)
@test nothing==run(`julia ../scripts/basis_plots.jl $model_path`)
@test nothing==run(`julia ../scripts/noise_plots.jl $noise_result_path`)
@test nothing==run(`julia ../scripts/popeonce.jl $ljhpath $model_path artifacts/model_output.h5`)
