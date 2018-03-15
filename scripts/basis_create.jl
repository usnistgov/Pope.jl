#!/usr/bin/env julia
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
        help ="The fraction of training pulses to keep. Each loop cuts a fraction of pulses
        with the highest residuals, after all loops, this fraction of pulses remain uncut."
    "tsvd_method"
        default = "TSVD"
        help = "which truncated SVD method to use, supports `TSVD` and `manual`.
        The results should be nearly identical, and `TSVD` (the default) is faster.
        But you can try `manual` as a sanity check if the basis vectors look weird"
end
parsed_args = parse_args(ARGS, s)
display(parsed_args);println()

using Pope.NoiseAnalysis
using Pope.LJH
using Pope
using HDF5

ljhdict = LJH.allchannels(parsed_args["pulse_file"]) # ordered dict mapping channel number to filename
outputh5 = h5open("temp.h5","w")
Pope.make_basis_all_channel(outputh5, ljhdict, parsed_args["noise_filename"],
    parsed_args["frac_keep"],
    parsed_args["n_loop"],
    parsed_args["n_pulses_for_train"],
    parsed_args["n_basis"],
    parsed_args["tsvd_method"])
close(outputh5)
