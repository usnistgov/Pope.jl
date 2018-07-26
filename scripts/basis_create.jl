#!/usr/bin/env julia
using ArgParse
s = ArgParseSettings()
@add_arg_table s begin
    "pulse_file"
        help = "name of the pulse containing ljh file to use to make basis"
        required = true
        arg_type = String
    "noise_file"
        help = "name of the noise_analysis hdf5 file to use to make basis"
        required = true
        arg_type = String
    "--outputfile", "-o"
        arg_type = String
        help="specify the path of the outputfile, otherwise it will make one up based on pulse_file"
    "--replaceoutput", "-r"
        help = "if this is present, it will overwrite any existing output files with the same name as it plans to use"
        action = :store_true
    "--n_pulses_for_train"
        arg_type = Int
        default = 3000
        help = "number of pulses for training"
    "--n_basis"
        arg_type = Int
        default = 6
        help = "number of basis vectors to calculate"
    "--n_loop"
        arg_type = Int
        default = 5
        help = "number of training loops"
    "--frac_keep"
        arg_type = Float64
        default = 0.8
        help ="The fraction of training pulses to keep. Each loop cuts a fraction of pulses
        with the highest residuals, after all loops, this fraction of pulses remain uncut."
    "--tsvd_method"
        default = "TSVD"
        help = "which truncated SVD method to use, supports `TSVD` and `manual`.
        The results should be nearly identical, and `TSVD` (the default) is faster.
        But you can try `manual` as a sanity check if the basis vectors look weird"
end
parsed_args = parse_args(ARGS, s)
using Pope.NoiseAnalysis
using Pope.LJH
using Pope
using HDF5
if parsed_args["outputfile"]==nothing
    parsed_args["outputfile"] = Pope.outputname(parsed_args["pulse_file"],"model")
end
display(parsed_args);println()
if !parsed_args["replaceoutput"] && isfile(parsed_args["outputfile"])
    println("intended output file $(parsed_args["outputfile"]) exists, pass --replaceoutput if you would like to overwrite it")
    exit(1) # anything other than 0 indicated process unsuccesful
end

ljhdict = LJH.allchannels(parsed_args["pulse_file"]) # ordered dict mapping channel number to filename
outputh5 = h5open(parsed_args["outputfile"],"w")
Pope.make_basis_all_channel(outputh5, ljhdict, parsed_args["noise_file"],
    parsed_args["frac_keep"],
    parsed_args["n_loop"],
    parsed_args["n_pulses_for_train"],
    parsed_args["n_basis"],
    parsed_args["tsvd_method"])
close(outputh5)
