#!/usr/bin/env julia
using ArgParse
using HDF5
using ARMA
using Pope: NoiseAnalysis, LJH

function analyze_one_file(filename::AbstractString, channum::Integer,
        outputname::AbstractString, nlags::Integer=0,
        nfreq::Integer=0; max_samples=50000000)
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
        nfreq = round_up_dft_length(nsamp)
    end

    autocorr = compute_autocorr(rawdata, nlags, max_exc=1000)
    psd = compute_psd(rawdata, nfreq, frametime, max_exc=1000)
    freq = NoiseAnalysis.psd_freq(nfreq, frametime)
    freqstep = freq[2]-freq[1]

    model = fitARMA(autocorr, 4, 4)

    noise = NoiseResult(autocorr, psd, samplesUsed, freqstep, filename)

    # Open the HDF5 file for writing
    NoiseAnalysis.marshal(noise, outputname, channum)
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
            help = "store the results in OUTPUTFILE (an HDF5 file)"
            arg_type = String
        "--replacefile", "-r"
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

    appendoutput = parsed_args["updateoutput"]
    clobberoutput = parsed_args["replacefile"]
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
                message = @sprintf("marshal(...) was forbidden to add new channels to existing file '%s'", hdf5filename)
                error(message)
            end
        end
        analyze_one_file(fname, channum, output, nlags, nfreq)
    end
end

main()
