#!/usr/bin/env julia

using ArgParse
using ARMA
using HDF5
using Printf
using Pope.NoiseAnalysis

delete!(ENV, "PYTHONPATH")
using PyCall, PyPlot
pdf = pyimport("matplotlib.backends.backend_pdf")

function parse_commandline()
    s = ArgParseSettings()
    s.description="""Make summary plots of HDF5 noise files (produced by
noise_analysis.jl)."""

    @add_arg_table s begin
        "--outputfile", "-o"
            help = "store the results in OUTPUTFILE (a PDF file) instead of the inferred file or files"
            arg_type = String
        "--replaceoutput", "-r"
            help = "delete and replace any existing output files (default: false)"
            action = :store_true
        "hdf5files"
            help = "1 or more HDF5 files to analyze"
            arg_type = String
            action = :store_arg
            nargs = '+'
    end

    return parse_args(s)
end

function main()
    parsed_args = parse_commandline()

    inputs = parsed_args["hdf5files"]
    if parsed_args["outputfile"] == nothing
        outputs = [splitext(input)[1]*".pdf" for input in inputs]
    else
        base,ext = splitext(parsed_args["outputfile"])
        outputs = [base*"_$(i)"*ext for i in 1:length(inputs)]
    end
    for (input,output) in zip(inputs, outputs)
        @show input, output
        pdffile = pdf.PdfPages(output)
        try
            noiseplots(input, pdffile)
        finally
            pdffile[:close]()
        end
        @show output
    end
end

function noiseplots(input::AbstractString, pdffile)
    NVERT = 4
    MAXCORRSAMPLES = 50
    h5open(input, "r") do hfile
        channels = [parse(Int, k) for k in names(hfile)]
        sort!(channels)

        fig = figure(1, figsize=(11.5, 8))
        allfigs = [fig]

        for (i,chan) in enumerate(channels)
            g = hfile["$(chan)/noise"]
            noise = NoiseAnalysis.hdf5load(g)
            p = noise.model.p
            q = noise.model.q
            Nf = length(noise.psd)
            N = length(noise.autocorr)
            println("Loaded noise data for $(chan)")

            vert = (i-1)%NVERT
            isbottom = i%NVERT == 0
            NHOR = 3
            if N > 2MAXCORRSAMPLES
                NHOR = 5
            end

            ax = subplot(NVERT,NHOR,1+vert*NHOR)
            freq = noise.freqstep*collect(0:Nf-1)
            dfreq = noise.freqstep
            psd_model = ARMA.model_psd(noise.model, Nf) / freq[end]
            loglog(freq[3:end], noise.psd[3:end], "r", freq[2:end], psd_model[2:end], "b")
            title("Chan $(chan) noise PSD")
            isbottom && xlabel("Frequency (Hz)")
            ylabel("PSD (arbs\$^2\$/Hz)")
            grid(true)

            ax = subplot(NVERT,NHOR,2+vert*NHOR)
            ac_model = ARMA.model_covariance(noise.model, N)
            plot(noise.autocorr, "r", ac_model, "b")
            plot([0,N], [0,0], color="gray")
            plot([0],noise.autocorr[1], "ro", [0],ac_model[1], "bo")
            title("Acorr, model($p,$q)")
            isbottom && xlabel("Samples")
            var = noise.autocorr[1]
            for j=1:p
                a = abs(noise.model.expampls[j])
                b = noise.model.expbases[j]
                phi = atan(imag(b), real(b))
                timeconst = -1.0/log(abs(b))
                msg = @sprintf("%.3f*exp(-t/%.3f)", a, timeconst)
                if abs(phi*N) > .01 && imag(b)<0
                    msg = @sprintf("period = %.2f", -2π/phi)
                else
                end
                text(N, var*(1-0.09*j), msg, ha="right", fontsize="small")
            end

            ax = subplot(NVERT,NHOR,3+vert*NHOR)
            plot(noise.autocorr-ac_model, "g")
            plot([0,N], [0,0], color="gray")
            title("Resid (data-model)")
            isbottom && xlabel("Samples")

            if N > 2MAXCORRSAMPLES
                ax = subplot(NVERT,NHOR,4+vert*NHOR)
                ac_model = ARMA.model_covariance(noise.model, MAXCORRSAMPLES)
                plot([0,MAXCORRSAMPLES], [0,0], color="gray")
                plot(noise.autocorr[1:MAXCORRSAMPLES], "r", ac_model, "b")
                plot([0],noise.autocorr[1], "ro", [0],ac_model[1], "bo")
                title("Acorr zoom")
                isbottom && xlabel("Samples")

                ax = subplot(NVERT,NHOR,5+vert*NHOR)
                plot([0,MAXCORRSAMPLES], [0,0], color="gray")
                plot(noise.autocorr[1:MAXCORRSAMPLES]-ac_model, "g")
                title("Resid zoom")
                isbottom && xlabel("Samples")
            end

            if vert == NVERT-1 || chan == channels[end]
                tight_layout()
                pdffile[:savefig](fig)
                println("Rendered a page")
                plt[:close](fig)
                fig = figure(1, figsize=(11.5, 8))
            end
        end
    end
end

@time main()
