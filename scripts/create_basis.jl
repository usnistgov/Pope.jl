using ArgParse
s = ArgParseSettings()
@add_arg_table s begin
    "pulse_file"
        help = "name of the pulse containing ljh file to use to make basis"
        # required = true
        default = "/Users/oneilg/.julia/v0.6/ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh"
    "noise_filename"
        help = "name of the noise_analysis hdf5 file to use to make basis"
        # required = true
        default = "/Users/oneilg/.julia/v0.6/ReferenceMicrocalFiles/ljh/20150707_C_noise.hdf5"
    "n_pulses_for_train"
        arg_type = Int
        default = 3000
    "n_basis"
        arg_type = Int
        default = 6
    "n_loop"
        arg_type = Int
        default = 5
    "frac_keep"
        arg_type = Float64
        default = 0.8
    "tsvd_method"
        default = "TSVD"
        help = "which truncated SVD method to use, supports `TSVD` and `manual`.
        The results should be nearly identical, and `TSVD` (the default) is faster.
        But you can try `manual` as a sanity check if the basis vectors look weird"
end
parsed_args = parse_args(ARGS, s)
display(parsed_args)

using Pope.NoiseAnalysis
using Pope.LJH
using TSVD



make_psr(data, basis) = basis*data
make_time_domain(psr, basis) = basis'*psr
function make_std_residuals(data, basis)
    psr = make_psr(data,basis)
    td = make_time_domain(psr,basis)
    residuals = std(data-td,1)[1,:]
end
function getall(ljh, maxrecords=typemax(Int))
    records = collect(ljh[1:min(Int(maxrecords),length(ljh))])
    pulses = Array{Float64,2}(ljh.record_nsamples,length(records))
    for (i,record) in enumerate(records)
        pulses[:,i]=record.data
    end
    pulses
end
function evenly_distributed_inds(inds,n_wanted)
    frac_keep = n_wanted/length(inds)
    keep_each_n = floor(Int,1/frac_keep)
    inds[1:keep_each_n:length(inds)]
end
function choose_new_train_inds(residuals, train_inds, frac_keep)
    n_keep = round(Int, frac_keep*length(train_inds))
    sort(train_inds, by = i -> residuals[i])[1:n_keep]
end
function train_loop(data,n_pulses_for_train, n_basis, n_loop, frac_keep_per_loop, make_basis)
    last_train_inds = train_inds = evenly_distributed_inds(1:size(data,2),n_pulses_for_train)
    for i=1:n_loop
        basis, singular_values = make_basis(data[:,train_inds],n_basis)
        residuals = make_std_residuals(data,basis)
        last_train_inds = train_inds
        train_inds = choose_new_train_inds(residuals, train_inds, frac_keep_per_loop)
        if i==n_loop # variables created in loop are not availble outside the loop
            return basis, residuals, last_train_inds, train_inds, singular_values
        end
    end
end
function TSVD_tsvd(data_train,n_basis)
    U, S, V = TSVD.tsvd(data_train, n_basis)
    U',S
end
function manual_tsvd(data_train, n_basis)
    U,S,V = svd(data_train)
    U[:,1:n_basis]',S[1:n_basis]
end
tsvd_dict = Dict("TSVD"=>TSVD_tsvd,"manual"=>manual_tsvd)


struct SVDBasis
    basis::Array{Float32,2} # unwhitened time domain representation, tall: basis*psr = reconsituted pulse
    projectors::Array{Float32,2} # whitened time domain representation, wide: projectors*data = psr
    noise_result::NoiseResult
end

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
end


function create_basis_one_channel(ljh, noise_result, frac_keep, n_loop, n_pulses_for_train, n_basis,
    tsvd_method_string)
    tsvd_func = tsvd_dict[tsvd_method_string]
    std_noise = sqrt(noise_result.autocorr[1]) # the first element in the autocorrelation is the variance
    data = getall(ljh, ceil(Int,n_pulses_for_train/frac_keep))
    frac_keep_per_loop = exp(log(frac_keep)/n_loop)
    duration = @elapsed begin
        basis, residuals, last_train_inds, train_inds, singular_values = train_loop(data,
        n_pulses_for_train, n_basis, n_loop, frac_keep_per_loop, tsvd_func)
    end
    std_residuals_all = make_std_residuals(data,basis)
    svdbasis = SVDBasis(basis,basis,noise_result)
    sortinds = sortperm(residuals)
    percentiles = [10:90;91:99]
    percentile_indicies = [round(Int,(p/100)*length(residuals)) for p in percentiles]
    svdbasis_with_info = SVDBasisWithCreationInfo(
    svdbasis, singular_values, data[:,percentile_indicies],
    std_residuals_all[percentile_indicies], percentiles,
    n_loop, noise_result.datasource, LJH.filename(ljh),
    std_residuals_all,tsvd_method_string, LJH.channel(ljh)
    )
    return svdbasis,svdbasis_with_info
end





using HDF5

function hdf5save(g::HDF5.DataFile, svdbasis::SVDBasis)
    g["basis"]=svdbasis.basis
    g["projectors"]=svdbasis.projectors
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
end


function hdf5load(T::Type{SVDBasis},g::HDF5.DataFile)
    SVDBasis(
    read(g["basis"]),
    read(g["projectors"]),
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
    read(g["channel_number"])
    )
end


function make_basis_one_channel(outputh5, ljhname, noise_filename, frac_keep, n_loop,
    n_pulses_for_train, n_basis, tsvd_method)
    ljh = ljhopen(ljhname)
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
    for (channel_number, ljhname) in ljhdict
        make_basis_one_channel(outputh5, ljhname, noise_filename, frac_keep, n_loop,
            n_pulses_for_train, n_basis, tsvd_method)
    end
end

ljhdict = LJH.allchannels(parsed_args["pulse_file"]) # ordered dict mapping channel number to filename
outputh5 = h5open("temp.h5","w")
make_basis_all_channel(outputh5, ljhdict, parsed_args["noise_filename"],
    parsed_args["frac_keep"],
    parsed_args["n_loop"],
    parsed_args["n_pulses_for_train"],
    parsed_args["n_basis"],
    parsed_args["tsvd_method"])
close(outputh5)

# h5open("temp.h5","w") do h5
#     g = g_create(h5,"$(svdbasiswithcreationinfo.channel_number)")
#     hdf5save(g,svdbasiswithcreationinfo)
# end

# ljh = ljhopen(parsed_args["pulse_file"])
# noise_result = NoiseAnalysis.hdf5load(parsed_args["noise_filename"],LJH.channel(ljh))
# svdbasis, svdbasiswithcreationinfo = create_basis_one_channel(ljh, noise_result,
#     parsed_args["frac_keep"],
#     parsed_args["n_loop"],
#     parsed_args["n_pulses_for_train"],
#     parsed_args["n_basis"],
#     parsed_args["tsvd_method"])

h5 = h5open("temp.h5","r")
names(h5["13"])
svdbasiswithcreationinfo_read = hdf5load(SVDBasisWithCreationInfo,h5["13"])
svdbasis_read = hdf5load(SVDBasis,h5["13/svdbasis"])
