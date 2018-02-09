#!/usr/bin/env julia
using ArgParse
using HDF5
using ARMA
using Pope: NoiseAnalysis, LJH

function analyze_one_file(filename::AbstractString, channum::Integer,
        outputname::AbstractString, nlags::Integer=0, nfreq::Integer=0;
        max_samples::Integer=50000000)
    @printf("Analyzing file %s (chan %3d) => %s\n", filename, channum, outputname)

    # Open the LJH file for reading
    f = LJHFile(filename)
    const frametime = LJH.frametime(f)
    const nsamp = LJH.record_nsamples(f)
    nrec = LJH.ljh_number_of_records(f)
    if nsamp*nrec > max_samples
        nrec = max_samples // nsamp
    end
    rawdata = vcat([rec.data for rec in f[1:nrec]]...)
    const samplesUsed = length(rawdata)

    if nlags <= 0
        nlags = nsamp
    end
    if nfreq <= 0
        nfreq = NoiseAnalysis.round_up_dft_length(nsamp)
    end

    autocorr = compute_autocorr(rawdata, nlags, max_exc=1000)
    psd = compute_psd(rawdata, nfreq, frametime, max_exc=1000)
    freq = NoiseAnalysis.psd_freq(nfreq, frametime)
    freqstep = freq[2]-freq[1]

    max_ARMA_order = 5
    model = fitARMA(autocorr, max_ARMA_order, pmin=1)

    noise = NoiseResult(autocorr, psd, samplesUsed, freqstep, filename, model)
    NoiseAnalysis.hdf5save(outputname, channum, noise)
end

function parse_commandline()
    s = ArgParseSettings()
    s.description="""Analyze one or more LJH data files containing noise data,
to determine the noise autocorrelation, power-spectral density, and best-fit
ARMA model. Also store the results in an HDF5 file. By default, will fail if the
output HDF5 file already exists, though you can specify -r to replace an existing
file or -u to update it by addition of new channels (noise analysis for existing
channels cannot be replaced)."""

    @add_arg_table s begin
        "--outputfile", "-o"
            help = "store the results in OUTPUTFILE (an HDF5 file) instead of the inferred file or files"
            arg_type = String
        # Example Input not implemented yet. It turns whatever_chan1.ljh into whatever_chan*.ljh, effectively.
        # "--exampleinput", "-e"
        #     help = "analyze all noise files for all channel numbers that otherwise match this example file name"
        #     arg_type = String
        "--replaceoutput", "-r"
            help = "delete and replace any existing output files (default: false)"
            action = :store_true
        "--updateoutput", "-u"
            help = "add channels to an existing output file (default: false)"
            action = :store_true
        "--nlags", "-n"
            help = "compute autocorrelation for this many lags (default: LJH record length)"
            arg_type = Int
            default = 0
        "--nfreq", "-f"
            help = "compute power spectrum for this many frequencies (default: LJH record length//2)"
            arg_type = Int
            default = 0
        "ljhfile"
            help = "1 or more LJH-format data files (optional if -p is used)"
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

    appendoutput = parsed_args["updateoutput"]
    clobberoutput = parsed_args["replaceoutput"]
    if clobberoutput && appendoutput
        error("Cannot specify both --updateoutput and --replacefile")
    end
    if clobberoutput
        appendoutput = true
    end

    nlags = parsed_args["nlags"]
    nfreq = parsed_args["nfreq"]
    println()

    alreadyclobbered = Set{String}()
    for fname in parsed_args["ljhfile"]
        full_prefix, channum = parse_filename(fname)
        output = full_prefix * "_noise.hdf5"
        if parsed_args["outputfile"] != nothing
            output = parsed_args["outputfile"]
        end

        if isfile(output)
            if clobberoutput && !(output in alreadyclobbered)
                push!(alreadyclobbered, output)
                rm(output)
            elseif !appendoutput
                message = @sprintf("noise_analysis.jl was not allowed to add new channels to existing file '%s'", output)
                error(message)
            end
        end
        analyze_one_file(fname, channum, output, nlags, nfreq)
    end
end

main()
