#!/usr/bin/env julia
using ArgParse
using HDF5

function analyze_one_file(filename::AbstractString, channum::Integer,
        outputname::AbstractString, overwrite::Bool)
    @printf("Analyzing file %s (chan %3d) => %s\n", filename, channum, outputname)
    chanstring = string(channum)
    if !isfile(outputname)
        h5open(outputname, "w") do x
            g_create(x, "noise")
        end
    end
    h5open(outputname, "r+") do noisefile
        noisegroup = noisefile["noise"]
        if chanstring in names(noisegroup)
            if !overwrite
                text = @sprintf("instructed not to overwrite existing HDF5 group noise/%s", chanstring)
                error(text)
            end
            g = noisegroup[chanstring]
        else
            g = g_create(noisegroup, chanstring)
        end

        @printf("Analysis here \n")
        
    end
end

function parse_commandline()
    s = ArgParseSettings()
    s.description="""Analyze one or more LJH data files containing noise data,
to determine the noise autocorrelation and power-spectral density, and store
the results in an LJH file."""

    @add_arg_table s begin

        "--outputfile", "-o"
            help = "store the results in OUTPUTFILE (an HDF5 file)"
            arg_type = String
        "--updateoutput", "-u"
            help = "update an existing output file (default: false)"
            action = :store_true
        "ljhfile"
            help = "an LJH-format data file "
            required = true
            arg_type = String
            action = :store_arg
            nargs = '+'
    end

    return parse_args(s)
end

function parse_filename(filename::AbstractString)
    dir, f = splitdir(filename)
    base, ext = splitext(f)
    parts = split(base, "_chan")
    prefix = join(parts[1:end-1], "")
    channum = parse(Int, parts[end])
    full_prefix = join([dir,prefix], "/")
    full_prefix, channum
end

function main()
    parsed_args = parse_commandline()

    overwrite = parsed_args["updateoutput"]

    for fname in parsed_args["ljhfile"]
        full_prefix, channum = parse_filename(fname)
        output = full_prefix * "_noise.hdf5"
        if parsed_args["outputfile"] != nothing
            output = parsed_args["outputfile"]
        end
        analyze_one_file(fname, channum, output, overwrite)
    end
end

main()
