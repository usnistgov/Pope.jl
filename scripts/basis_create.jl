#!/bin/bash
#=
JULIA="${JULIA:-julia}"
JULIA_CMD="${JULIA_CMD:-$JULIA --color=yes --startup-file=no}"
# below gets the directory name of the script, even if there is a symlink involved
# from https://stackoverflow.com/questions/59895/get-the-source-directory-of-a-bash-script-from-within-the-script-itself
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
export JULIA_PROJECT=$DIR/..
export JULIA_LOAD_PATH=@:@stdlib  # exclude default environment
exec $JULIA_CMD -e 'include(popfirst!(ARGS))' "$SOURCE" "$@"
=#
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
        help ="""The fraction of training pulses to keep. Each loop cuts a fraction of pulses
        with the highest residuals, after all loops, this fraction of pulses remain uncut."""
    "--tsvd_method"
        default = "noisemass3"
        help = """which truncated SVD method to use, supports `TSVDmass3`, `noisemass3`, `TSVD`, and `full`.
        The default is `noisemass3`, in which the usual MASS method is applied (find the pulse
        average, a time-correction, and a constant, and use SVD on the residuals to find any
        additional components). The `TVSDmass3` is like `noisemass3` but uses approximate ARMA models.
        The other 2 methods just apply (truncated) SVD to the training data.
        The results of the last two should be nearly identical, and `TSVD` is faster.
        But you can try `full`, which computes the full SVD and retains the leading `n_basis` vectors,
        as a sanity check if the basis vectors look weird.
        Note that for methods TSVDmass3 and noisemass3, the value of `n_basis` must be at least 3."""
    "--maxchannels"
        default = 1000000
        help = "process at most this many channels, in order from lowest channel number"
        arg_type = Int
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

ljhdict = LJH.allchannels(parsed_args["pulse_file"],parsed_args["maxchannels"]) # ordered dict mapping channel number to filename
outputh5 = h5open(parsed_args["outputfile"],"w")
Pope.make_basis_all_channel(outputh5, ljhdict, parsed_args["noise_file"],
    parsed_args["frac_keep"],
    parsed_args["n_loop"],
    parsed_args["n_pulses_for_train"],
    parsed_args["n_basis"],
    parsed_args["tsvd_method"])
close(outputh5)
