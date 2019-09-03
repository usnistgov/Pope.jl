using TSVD
using LinearAlgebra
using ToeplitzMatrices
using ARMA

make_mpr(data, basis) = pinv(basis)*data
make_time_domain(mpr, basis) = basis*mpr
function make_std_residuals(data, basis)
    mpr = make_mpr(data,basis) # model pulse reduced
    td = make_time_domain(mpr,basis)
    std_residuals = std(data-td, dims=1)[1,:]
end

function getall(ljh, maxrecords=typemax(Int))
    records = collect(ljh[1:min(Int(maxrecords),length(ljh))])
    pulses = Array{Float32}(undef, ljh.record_nsamples,length(records))
    for (i,record) in enumerate(records)
        pulses[:,i]=record.data
    end
    pulses
end

function evenly_distributed_inds(inds,n_wanted)
    frac_keep = n_wanted/length(inds)
    keep_each_n = max(1,floor(Int,1/frac_keep))
    inds[1:keep_each_n:length(inds)]
end

function choose_new_train_inds(residuals, train_inds, frac_keep)
    n_keep = round(Int, frac_keep*length(train_inds))
    sort(train_inds, by = i -> residuals[i])[1:n_keep]
end

function train_loop(data, n_pulses_for_train, n_basis, n_presamples, n_loop, frac_keep_per_loop, make_basis)
    last_train_inds = train_inds = evenly_distributed_inds(1:size(data,2),n_pulses_for_train)
    # Use only a 3-Dimensional basis the first time through. This helps reject pileup before it
    # can sneak into the SVD.
    nb = min(n_basis, 3)
    for i=1:n_loop
        basis, singular_values = make_basis(data[:,train_inds],nb)
        residuals = make_std_residuals(data,basis)
        last_train_inds = train_inds
        train_inds = choose_new_train_inds(residuals, train_inds, frac_keep_per_loop)
        if i==n_loop # variables created in loop are not availble outside the loop
            return basis, residuals, last_train_inds, train_inds, singular_values
        end
        nb = n_basis
    end
end

function TSVD_tsvd(data_train::Matrix{<:AbstractFloat},n_basis)
    U, S, V = TSVD.tsvd(data_train, n_basis)
    U, S
end

"""    TSVD_tsvd_mass3(data_train::Matrix{<:AbstractFloat}, n_basis, n_presamples, noise_model::ARMA.ARMAModel, noise_solver::ARMA.ARMASolver)

This function is called as the first step towards creating a basis with `n_basis` elements (minimum 3).
Elements will be 1) constant, 2) derivative-like, 3) pulse-like with first `n_presamples` equal to zero.
Elements 4 and higher are based on SVD of the noise whitened residuals after projecting into a basis of
just the first 3 elements. This ensures that adding additional components will not change the projector
for the first 3 components, and therefore the energy resolution obtained with only the first 3 projectors
will be independing of number of components.

The basis is paired with projectors, which allow you to project into the basis while minimizing
the noise whitened residuals (aka the mahalonobis distance).

This function returns `U,S` much like a truncated singular value decomposition, but such that the
basis caluclated from `U,S` will meet the description above."""
function TSVD_tsvd_mass3(data_train::Matrix{<:AbstractFloat}, n_basis, n_presamples,
        noise_model::ARMA.ARMAModel, noise_solver::ARMA.ARMASolver)
    @assert n_basis>=3 "mean, derivative and average pulse are 3 components, must request at least 3 components"
    # Average pulse is the pretrigger-mean-subtracted average pulse, rescaled to have a maximum value of 1.0
    average_pulse = mean(data_train, dims=2)[:]
    if n_presamples > 0
        average_pulse .-= mean(average_pulse[1:n_presamples])
    end
    average_pulse[1:n_presamples] .= 0.0
    average_pulse /= maximum(average_pulse)
    # Calculate the derivative like component; assume clean baseline, so low derivative at start
    derivative_like = [0.0;diff(average_pulse)]
    constant_component = ones(size(data_train,1))
    mass3_basis = hcat(constant_component,derivative_like,average_pulse)
    if n_basis == 3
        return mass3_basis, [NaN,NaN,NaN]
    end
    projectors3, _ = computeprojectors(mass3_basis, noise_model)
    mpr = projectors3 * data_train # model pulse reduced
    td = mass3_basis * mpr
    data_residual = data_train .- td
    # Whiten residual before taking the TSVD
    white_residual = ARMA.whiten(noise_solver, data_residual)
    Uwhite, S, _ = TSVD.tsvd(white_residual, n_basis-3)
    # Unwhiten and renormalize U before combining
    Uunnorm = ARMA.unwhiten(noise_solver, Uwhite)
    U = Uunnorm ./ sqrt.(sum(Uunnorm.^2, dims=1))
    U_combined = hcat(mass3_basis,U)
    S_combined = vcat([NaN,NaN,NaN],S) # first 3 elemnts are not from svd, have no meaningful singular value
    U_combined, S_combined
end

"""
    TSVD_tsvd_mass3(data_train::Matrix{<:AbstractFloat}, n_basis, n_presamples, autocorr::Vector)

Create mass3+SVD as the other method does, but use the noise autocorrelation (`autocorr`)
instead of using a noise model. This should mirror the MASS behavior.
"""
function TSVD_tsvd_mass3(data_train::Matrix{<:AbstractFloat}, n_basis, n_presamples, autocorr::Vector)
    @assert n_basis>=3 "mean, derivative and average pulse are 3 components, must request at least 3 components"
    # Average pulse is the pretrigger-mean-subtracted average pulse, rescaled to have a maximum value of 1.0
    average_pulse = mean(data_train, dims=2)[:]
    if n_presamples > 0
        average_pulse .-= mean(average_pulse[1:n_presamples])
    end
    average_pulse[1:n_presamples] .= 0.0
    average_pulse /= maximum(average_pulse)
    # Calculate the derivative like component; assume clean baseline, so low derivative at start
    derivative_like = [0.0;diff(average_pulse)]
    constant_component = ones(size(data_train,1))
    mass3_basis = hcat(constant_component,derivative_like,average_pulse)
    if n_basis == 3
        return mass3_basis, [NaN,NaN,NaN]
    end
    projectors3, _ = computeprojectors(mass3_basis, autocorr)
    mpr = projectors3 * data_train # model pulse reduced
    td = mass3_basis * mpr
    data_residual = data_train .- td
    # Whiten residual before taking the TSVD
    R = SymmetricToeplitz(autocorr)
    Winv = cholesky(R).L  # The inverse of Winv will whiten a data record.
    white_residual = Winv \ data_residual
    Uwhite, S, _ = TSVD.tsvd(white_residual, n_basis-3)
    # Unwhiten and renormalize U before combining
    Uunnorm = Winv * Uwhite
    U = Uunnorm ./ sqrt.(sum(Uunnorm.^2, dims=1))
    U_combined = hcat(mass3_basis, U)
    S_combined = vcat([NaN,NaN,NaN], S) # first 3 elemnts are not from svd, have no meaningful singular value
    U_combined, S_combined
end

function full_svd(data_train, n_basis)
    U,S,V = svd(data_train)
    U[:,1:n_basis], S[1:n_basis]
end
tsvd_dict = Dict(
    "TSVD" => TSVD_tsvd,
    "full" => full_svd,
    "noisemass3" => TSVD_tsvd_mass3,
    "TSVDmass3" => TSVD_tsvd_mass3)


struct SVDBasis <: AbstractBasisAnalyzer
    basis::Array{Float32,2} # unwhitened time domain representation, tall: basis*mpr = reconsituted pulse
    projectors::Array{Float32,2} # whitened time domain representation, wide: projectors*data = mpr
    projector_covariance::Array{Float32,2}
    noise_result::NoiseAnalysis.NoiseResult
end
(a::SVDBasis)(record) = record2dataproduct(a,record)


struct SVDBasisWithCreationInfo
    svdbasis::SVDBasis
    singular_values::Vector{Float32}
    example_pulses::Array{UInt16,2}
    std_residuals_of_example_pulses::Vector{Float32}
    percentiles_of_sample_pulses::Vector{Float32}
    n_loop::Int
    noise_model_file::String
    pulse_file::String
    std_residuals::Vector{Float32}
    tsvd_method::String
    channel_number::Int
    noise_std_dev::Float64
end

function create_basis_one_channel(ljh, noise_result, frac_keep, n_loop, n_pulses_for_train, n_basis,
    tsvd_method_string)
    data = getall(ljh, ceil(Int,n_pulses_for_train/frac_keep))
    create_basis_one_channel(data, noise_result, frac_keep, n_loop,
        n_pulses_for_train, n_basis, tsvd_method_string,
        LJH.first_rising_sample(ljh[1]),
        LJH.filename(ljh), LJH.channel(ljh))
end


function create_basis_one_channel(data::Matrix{<:AbstractFloat}, noise_result, frac_keep, n_loop, n_pulses_for_train, n_basis,
    tsvd_method_string, n_presamples, datasource_filename, datasource_channel)
    tsvd_func = tsvd_dict[tsvd_method_string]
    if tsvd_method_string == "TSVDmass3"
        noise_solver = ARMA.ARMASolver(noise_result.model, size(data, 1))
        function tsvd_closure(data, n_basis)
            TSVD_tsvd_mass3(data, n_basis, n_presamples, noise_result.model, noise_solver)
        end
        tsvd_func = tsvd_closure
    elseif tsvd_method_string == "noisemass3"
        function tsvd_closure2(data, n_basis)
            TSVD_tsvd_mass3(data, n_basis, n_presamples, noise_result.autocorr)
        end
        tsvd_func = tsvd_closure2
    end

    std_noise = sqrt(noise_result.autocorr[1]) # the first element in the autocorrelation is the variance
    frac_keep_per_loop = exp(log(frac_keep)/n_loop)
    basis, residual_stds, last_train_inds, train_inds, singular_values = train_loop(data,
        n_pulses_for_train, n_basis, n_presamples, n_loop, frac_keep_per_loop, tsvd_func)
    if tsvd_method_string == "noisemass3"
        projectors, pcovar = computeprojectors(basis,noise_result.autocorr)
    else
        projectors, pcovar = computeprojectors(basis,noise_result.model)
    end
    svdbasis = SVDBasis(
        basis,
        projectors,
        pcovar,
        noise_result)
    sortinds = sortperm(residual_stds)
    percentiles = [10:10:90; 91:99]
    percentile_indicies = sortinds[[round(Int,(p/100)*length(residual_stds)) for p in percentiles]]
    example_pulses = round.(UInt16,data[:,percentile_indicies])
    svdbasis_with_info = SVDBasisWithCreationInfo(
        svdbasis, singular_values, example_pulses,
        residual_stds[percentile_indicies], percentiles,
        n_loop, noise_result.datasource, datasource_filename,
        residual_stds, tsvd_method_string, datasource_channel,
        √(svdbasis.noise_result.autocorr[1])
        )
    return svdbasis,svdbasis_with_info
end

function hdf5save(g::HDF5.DataFile, svdbasis::SVDBasis)
    g["basis"]=svdbasis.basis
    g["projectors"]=svdbasis.projectors
    g["projector_covariance"]=svdbasis.projector_covariance
    Pope.NoiseAnalysis.hdf5save(g_create(g,"noise_result"),svdbasis.noise_result)
end

function hdf5save(g::HDF5.DataFile, x::SVDBasisWithCreationInfo)
    hdf5save(g_create(g,"svdbasis"),x.svdbasis)
    g["singular_values"]=x.singular_values
    g["example_pulses"]=x.example_pulses
    g["std_residuals_of_example_pulses"]=x.std_residuals_of_example_pulses
    g["percentiles_of_sample_pulses"]=x.percentiles_of_sample_pulses
    g["n_loop"]=x.n_loop
    g["noise_model_file"]=x.noise_model_file
    g["pulse_file"]=x.pulse_file
    g["std_residuals"]=x.std_residuals
    g["tsvd_method"]=x.tsvd_method
    g["channel_number"]=x.channel_number
    g["noise_std_dev"]=x.noise_std_dev
end


function hdf5load(T::Type{SVDBasis},g::HDF5.DataFile)
    SVDBasis(
    read(g["basis"]),
    read(g["projectors"]),
    read(g["projector_covariance"]),
    NoiseAnalysis.hdf5load(g["noise_result"])
    )
end


function hdf5load(T::Type{SVDBasisWithCreationInfo},g::HDF5.DataFile)
    SVDBasisWithCreationInfo(
    hdf5load(SVDBasis,g["svdbasis"]),
    read(g["singular_values"]),
    read(g["example_pulses"]),
    read(g["std_residuals_of_example_pulses"]),
    read(g["percentiles_of_sample_pulses"]),
    read(g["n_loop"]),
    read(g["noise_model_file"]),
    read(g["pulse_file"]),
    read(g["std_residuals"]),
    read(g["tsvd_method"]),
    read(g["channel_number"]),
    read(g["noise_std_dev"])
    )
end


function make_basis_one_channel(outputh5, ljhname, noise_filename, frac_keep, n_loop,
    n_pulses_for_train, n_basis, tsvd_method)
    ljh = LJH.ljhopen(ljhname)
    @show LJH.channel(ljh)
    @show ljhname
    @show ljh
    noise_result = NoiseAnalysis.hdf5load(noise_filename,LJH.channel(ljh))
    svdbasis, svdbasiswithcreationinfo = create_basis_one_channel(ljh, noise_result,
        frac_keep,
        n_loop,
        n_pulses_for_train,
        n_basis,
        tsvd_method)
    hdf5save(g_create(outputh5,"$(LJH.channel(ljh))"), svdbasiswithcreationinfo)
end

function make_basis_all_channel(outputh5, ljhdict, noise_filename, frac_keep, n_loop,
    n_pulses_for_train, n_basis, tsvd_method)
    noise_h5 = h5open(noise_filename,"r")
    noise_channels = sort!(parse.(Int,names(noise_h5)))
    ljh_channels = keys(ljhdict)
    bothchannels = sort!(intersect(noise_channels,ljh_channels))
    @show noise_channels
    @show ljh_channels
    @show bothchannels
    for channel_number in bothchannels
        println("making basis for channel $channel_number")
        ljhname = ljhdict[channel_number]
        try
            make_basis_one_channel(outputh5, ljhname, noise_filename, frac_keep, n_loop,
                n_pulses_for_train, n_basis, tsvd_method)
        catch ex
            print("channel $channel_number failed")
            print(ex)
        end
    end
    println("Channels in noise_file but not in ljh: $(setdiff(noise_channels,ljh_channels))")
    println("Channels in ljh but not in noise_file: $(setdiff(ljh_channels,noise_channels))")
end
