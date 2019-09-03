#!/usr/bin/env julia --project

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
end
parsed_args = parse_args(ARGS, s)
if parsed_args["outdir"] == nothing
    parsed_args["outdir"] = parsed_args["ljh_file"]*prod(parsed_args["endings"])
end
display(parsed_args);println()
using Pope.LJH
using HDF5
using JSON

function off_header(ljh::LJH.LJHFile, z::Pope.SVDBasisWithCreationInfo)
    offVersion = "0.1.0"
    offHeader = Dict(
        "FileFormatVersion" => offVersion,
        "FramePeriodSeconds" => LJH.frameperiod(ljh),
        "NumberOfBases" => size(z.svdbasis.projectors)[1],
        "FileFormat" => "OFF"
    )
    offHeader["ModelInfo"]=Dict(
        "Projectors" =>Dict(
            "RowMajorFloat64ValuesBase64" =>base64encode(transpose(Float64.(z.svdbasis.projectors))),
            "Rows" =>size(z.svdbasis.projectors)[1],
            "Cols" =>size(z.svdbasis.projectors)[2]
    ),
        "Basis" =>Dict(
            "RowMajorFloat64ValuesBase64" =>base64encode(transpose(Float64.(z.svdbasis.basis))),
            "Rows" =>size(z.svdbasis.basis)[1],
            "Cols" =>size(z.svdbasis.basis)[2]
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
    return JSON.json(offHeader,4)
end

ljh_files = [parsed_args["ljh_file"]*ending for ending in parsed_args["endings"]]
@show ljh_files
@show parsed_args["endings"]



earliest_timestamp_usec = [typemax(Int64) for i in ljh_files]
latest_timestamp_usec = [typemin(Int64) for i in ljh_files]
# make sure the directory exists
isdir(parsed_args["outdir"]) || mkdir(parsed_args["outdir"])
HDF5.h5open(parsed_args["model_file"],"r") do h5
    channels_processed = 0
    for name in names(h5)
        channels_processed >= parsed_args["maxchannels"] && break
        channum = parse(Int,name)
        offFilename = joinpath(parsed_args["outdir"],parsed_args["outdir"]*"_chan$(channum).off")
        header_written = false
        z = Pope.hdf5load(Pope.SVDBasisWithCreationInfo,h5[name])
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
                if !header_written
                    write(f, off_header(ljh,z))
                    header_written = true
                end
                earliest_timestamp_usec[i] = min(ljh[1].timestamp_usec, earliest_timestamp_usec[i])
                latest_timestamp_usec[i] = max(ljh[end].timestamp_usec, latest_timestamp_usec[i])
                channels_processed += 1
                for record in ljh
                    dp = Pope.record2dataproduct(z.svdbasis,record)
                    write(f,Int32(dp.nsamples), Int32(dp.first_rising_sample-4), Int64(dp.frame1index),
                    Int64(dp.timestamp_usec*1000), Float32(mean(record.data[1:dp.first_rising_sample-3])),
                    Float32(dp.residual_std), Float32.(dp.reduced))
                end # end of loop over ljh
            end # end of loop over parsed_args["ljh_files"]
        end # end of open do block
    end # end of loop over channels
end # end of h5open do block

experimental_state_filename = joinpath(parsed_args["outdir"],parsed_args["outdir"]*"_experiment_state.txt")
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
