#!/usr/bin/env julia

# Parse command-line first, so a failure can be detected before the compilation
# or execution of any code unrelated to argument parsing.
using ArgParse

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
        "--replaceoutput", "-r"
            help = "delete and replace any existing output files"
            action = :store_true
        "--nlags", "-n"
            help = "compute autocorrelation for this many lags (default: LJH record length)"
            arg_type = Int
            default = 0
        "--nfreq", "-f"
            help = "compute power spectrum for this many frequencies (default: LJH record length//2)"
            arg_type = Int
            default = 0
        "pulse_file"
            help = "name of the pulse containing single ljh noise file, all channels will be procssed"
            required = true
            arg_type = String
        "--dontcrash"
            help = "pass this to move on past any channel that fails"
            action = :store_true
        "--maxchannels"
            default = 10^4
            arg_type = Int
    end
    return parse_args(s)
end
parsed_args = parse_commandline()

using Pope.LJH
if parsed_args["outputfile"]==nothing
    parsed_args["outputfile"] = Pope.outputname(parsed_args["pulse_file"],"noise")
end
display(parsed_args);println()
if !parsed_args["replaceoutput"] && isfile(parsed_args["outputfile"])
    println("intended output file $(parsed_args["outputfile"]) exists, pass --replaceoutput if you would like to overwrite it")
    exit(1) # anything other than 0 indicated process unsuccesful
end
using HDF5
using ARMA
using Pope.NoiseAnalysis
outputh5 = h5open(parsed_args["outputfile"],"w")
ljhdict = LJH.allchannels(parsed_args["pulse_file"],parsed_args["maxchannels"]) # ordered dict mapping channel number to filename
function analyze_one_file(filename::AbstractString, channum::Integer,
        outputh5::HDF5.HDF5File, nlags::Integer=0, nfreq::Integer=0;
        max_samples::Integer=50000000)

    # Open the LJH file for reading
    f = LJHFile(filename)
    frametime = LJH.frametime(f)
    nsamp = LJH.record_nsamples(f)
    nrec = LJH.ljh_number_of_records(f)
    if nsamp*nrec > max_samples
        nrec = max_samples // nsamp
    end
    rawdata = vcat([rec.data for rec in f[1:nrec]]...)
    samplesUsed = length(rawdata)

    if length(rawdata) == 0
        error("rawdata has length=0 for $filename")
    elseif all(rawdata.==rawdata[1])
        error("rawdata is all the same value $(rawdata[1]) for $filename")
    end

    if nlags <= 0
        nlags = nsamp
    end
    if nfreq <= 0
        nfreq = NoiseAnalysis.round_up_dft_length(div(nsamp, 2)) + 1
    end

    autocorr = compute_autocorr(rawdata, nlags, max_exc=1000)
    psd = compute_psd(rawdata, nfreq, frametime, max_exc=1000)
    freq = NoiseAnalysis.psd_freq(nfreq, frametime)
    freqstep = freq[2]-freq[1]

    max_ARMA_order = 5
    # outputh5["noise_analysis_autocorr_input/chan$channum"]=autocorr # save some data for debugging
    model = fitARMA(autocorr, max_ARMA_order, pmin=1)

    noise = NoiseResult(autocorr, psd, samplesUsed, freqstep, filename, model)
    NoiseAnalysis.hdf5save(outputh5, channum, noise)
end

if length(ljhdict) == 0
    println("Analyzed 0 files")
    exit()
end

for (channum, ljhname) in ljhdict
    println("Analyzing $ljhname")
    try
        analyze_one_file(ljhname, channum, outputh5, parsed_args["nlags"], parsed_args["nfreq"])
    catch ex
        if !parsed_args["dontcrash"]
            rethrow(ex)
        else
            println("$ljhname FAILED noise analysis")
            println(ex)
        end
    end
end
