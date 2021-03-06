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
s = ArgParseSettings(description="Coallate ljh files and convert to off with given model file\n"*
"example usage:\n"*
"./ljh2off.jl 20181205_B/20181205_B_model.hdf5 20181205_ --endings=B C\n"
)
@add_arg_table s begin
    "model_file"
        help = "name of the hdf5 with basis to use"
        required = true
        arg_type = String
    "ljh_file"
        help = "name of the pulse files containing ljh file to use to make basis, will process all channels"
        required = true
        arg_type = String
    "--endings"
        nargs = '+'
        help = "a series of endings appended to ljh_file, eg A B C"
        default = String[""]
        arg_type = String
    "--maxchannels"
        default = 10000
        help = "process at most this many channels, in order from lowest channel number"
        arg_type = Int
    "--outdir"
        arg_type = String
        help ="path to the output directory, otherwise calculate automatically"
    "--replaceoutput", "-r"
        help = "delete and replace any existing output files"
        action = :store_true
end
parsed_args = parse_args(ARGS, s)
if parsed_args["outdir"] == nothing
    parts = splitpath(parsed_args["ljh_file"])
    parts[end] = "off"
    ljhpathPlusoff = joinpath(parts...)
    parsed_args["outdir"] = ljhpathPlusoff*prod(parsed_args["endings"])
end
display(parsed_args);println()
using Pope
using Pope.LJH
using HDF5
using JSON
import Statistics

function off_header_json(ljh::LJH.LJHFile, z::Pope.SVDBasisWithCreationInfo)
    offVersion = "0.2.0" # version 0.2.0 has projectors as binary after the header
    offHeader = Dict(
        "FileFormatVersion" => offVersion,
        "FramePeriodSeconds" => LJH.frameperiod(ljh),
        "NumberOfBases" => size(z.svdbasis.projectors)[1],
        "FileFormat" => "OFF"
    )
    offHeader["ModelInfo"]=Dict(
        "Projectors" =>Dict(
            "Rows" =>size(z.svdbasis.projectors)[1],
            "Cols" =>size(z.svdbasis.projectors)[2],
            "SavedAs" => "float64 binary data after header and before records. projectors first then basis, nbytes = rows*cols*8 for each projectors and basis"
    ),
        "Basis" =>Dict(
            "Rows" =>size(z.svdbasis.basis)[1],
            "Cols" =>size(z.svdbasis.basis)[2],
            "SavedAs" => "float64 binary data after header and before records. projectors first then basis, nbytes = rows*cols*8 for each projectors and basis"
    ),
        "NoiseStandardDeviation" => z.noise_std_dev,
        "NoiseModelFile" => z.noise_model_file,
        "PulseFile" => z.pulse_file,
        "ModelFile" => abspath(parsed_args["ljh_file"])
    )
    offHeader["ReadoutInfo"] = Dict(
        "ColumnNum" => LJH.column(ljh),
        "RowNum" => LJH.row(ljh),
        "NumberOfColumns" => ljh.headerdict["Number of columns"],
        "NumberOfRows" => ljh.headerdict["Number of rows"],
    )
    offHeader["CreationInfo"]=Dict(
        "SourceName" => "ljh2off.jl"
    )
    return JSON.json(offHeader,4) # includes "\n" termination
end

function write_off_header(io, ljh, z)
    nheader = write(io, off_header_json(ljh, z)) #  includes "\n" termination
    # write the projectors as float64 row-major (julia arrays are column major) binary after the header
    nprojectors = write(io, transpose(Float64.(z.svdbasis.projectors)))
    nbasis = write(io, transpose(Float64.(z.svdbasis.basis)))
end

ljh_files = [parsed_args["ljh_file"]*ending for ending in parsed_args["endings"]]
@show ljh_files
@show parsed_args["endings"]


earliest_timestamp_usec = [typemax(Int64) for i in ljh_files]
latest_timestamp_usec = [typemin(Int64) for i in ljh_files]
# make sure the directory exists
outputDir = parsed_args["outdir"]
offPrefix = splitpath(outputDir)[end]
if isdir(outputDir)
    if parsed_args["replaceoutput"]
        rm(outputDir, force=true, recursive=true)
    else
        println("outdir $(outputDir) exists, pass --replaceoutput to overwrite")
        println("exiting")
        exit(1)
    end
end
mkdir(outputDir)
HDF5.h5open(parsed_args["model_file"],"r") do h5
    channels_processed = 0
    channums = sort(parse.(Int,names(h5))) # parse to int early so we can sort
    for channum in channums
        channels_processed >= parsed_args["maxchannels"] && break
        offPrefix = splitpath(outputDir)[end]
        offFilename = joinpath(outputDir, offPrefix*"_chan$(channum).off")
        z = Pope.hdf5load(Pope.SVDBasisWithCreationInfo,h5["$channum"])
        open(offFilename,"w") do f
            for (i,ljhbase) in enumerate(ljh_files)
                dir, base, ext = LJH.dir_base_ext(ljhbase)
                ljh_filename = joinpath(dir,base)*"_chan$(channum)$(ext)"
                ljh = try
                    LJH.LJHFile(ljh_filename)
                catch ex
                    println("Channel $channum ljh file failed to open: $ljh_filename")
                    println(ex)
                    continue
                end
                println("$ljh_filename => $offFilename")
                if i==1 #write header when processing first ljh file
                    write_off_header(f,ljh,z)
                    header_written = true
                end
                earliest_timestamp_usec[i] = min(ljh[1].timestamp_usec, earliest_timestamp_usec[i])
                latest_timestamp_usec[i] = max(ljh[end].timestamp_usec, latest_timestamp_usec[i])
                channels_processed += 1
                for record in ljh
                    dp = Pope.record2dataproduct(z.svdbasis,record)
                    write(f,Int32(dp.nsamples), Int32(dp.first_rising_sample-4), Int64(dp.frame1index),
                    Int64(dp.timestamp_usec*1000), Float32(Statistics.mean(record.data[1:dp.first_rising_sample-3])),
                    Float32(dp.residual_std), Float32.(dp.reduced))
                end # end of loop over ljh
            end # end of loop over parsed_args["ljh_files"]
        end # end of open do block
    end # end of loop over channels
end # end of h5open do block

experimental_state_filename = joinpath(outputDir, offPrefix*"_experiment_state.txt")
state_names = parsed_args["endings"]
@show state_names
@show experimental_state_filename
open(experimental_state_filename,"w") do f
    write(f,"# unix time in nanoseconds, state label\n")
    write(f,string(earliest_timestamp_usec[1]*1000),", ", "START\n")
    for (i, timestamp_usec) in enumerate(earliest_timestamp_usec)
        write(f, string(timestamp_usec*1000),", ",state_names[i],"\n")
    end
    write(f,string(latest_timestamp_usec[end]*1000),", ", "END\n")
end
