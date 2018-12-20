#!/usr/bin/env julia
using ArgParse
s = ArgParseSettings(usage="./ljh2off.jl 20181205_B/ 20181205_B/20181205_B_model.hdf5")
@add_arg_table s begin
    "ljh_file"
        help = "name of the pulse containing ljh file to use to make basis, will process all channels"
        required = true
        arg_type = String
    "model_file"
        help = "name of the noise_analysis hdf5 file to use to make basis"
        required = true
        arg_type = String
    "--maxchannels"
        default = 10000
        help = "process at most this many channels, in order from lowest channel number"
        arg_type = Int
end
parsed_args = parse_args(ARGS, s)
display(parsed_args);println()
using Pope.LJH
using HDF5
using JSON

ljhdict = LJH.allchannels(parsed_args["ljh_file"],parsed_args["maxchannels"]) # ordered dict mapping channel number to filename
HDF5.h5open(parsed_args["model_file"],"r") do h5
for (channum, ljh_filename) in ljhdict
    # LJH.allchannels only contains existing files
    ljh = try
        LJH.LJHFile(ljh_filename)
    catch ex
        println("Channel $channum ljh file failed to open: $ljh_filename")
        println(ex)
        continue
    end
    offFilename = splitext(ljh_filename)[1]*".off"
    if !("$channum" in names(h5))
        println("Channel $channum has no model in model file, skipping")
        continue
    end
    println("$ljh_filename => $offFilename")
    z = Pope.hdf5load(Pope.SVDBasisWithCreationInfo,h5["$channum"])
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
    ))
    offHeader["ReadoutInfo"] = Dict(
        "ColumnNum" => LJH.column(ljh),
        "RowNum" => LJH.row(ljh),
        "NumberOfColumns" => ljh.headerdict["Number of columns"],
        "NumberOfRows" => ljh.headerdict["Number of rows"],
    )
    offHeader["CreationInfo"]=Dict(
        "SourceName" => "ljh2off.jl"
    )
    headerString = JSON.json(offHeader,4)
    open(offFilename,"w") do f
        write(f, headerString)
        for record in ljh
            dp = Pope.record2dataproduct(z.svdbasis,record)
            write(f,Int32(dp.nsamples), Int32(dp.first_rising_sample-4), Int64(dp.frame1index),
            Int64(dp.timestamp_usec*1000), Float32(mean(record.data[1:dp.first_rising_sample-3])),
            Float32(dp.residual_std), Float32.(dp.reduced))
        end # end of loop over ljh
    end # end of open do block
end # end of loop over ljhdict
end # end of h5open do block
