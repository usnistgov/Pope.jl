#!/usr/bin/env julia

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using ArgParse
s = ArgParseSettings()
@add_arg_table s begin
    "basisfile"
        help = "name of the HDF5 containing basis and creation info"
        required = true
    "--outputfile","-o"
        help = "the output pdf file path, otherwise it will make up a name"

end

delete!(ENV, "PYTHONPATH")
using PyCall
using PyPlot
using HDF5
using Pope
using LinearAlgebra
using Statistics
parsed_args = parse_args(ARGS, s)
if parsed_args["outputfile"]==nothing
    parsed_args["outputfile"] = Pope.outputname(parsed_args["basisfile"],"plots","pdf")
end
display(parsed_args);println()
pdf = pyimport("matplotlib.backends.backend_pdf")

function titleme(basisinfo)
    title("Chan $(basisinfo.channel_number)
    Noise file: $(basename(basisinfo.noise_model_file))
    Pulse file: $(basename(basisinfo.pulse_file))")
end


function plot_model_and_residuals(basisinfo)
    figure(figsize=(10,10))
    subplot(311)
    Nsamp, Nb = size(basisinfo.svdbasis.basis)
    artists=plot(basisinfo.svdbasis.basis)
    xlabel("Sample number")
    titleme(basisinfo)
    legend(artists, basisinfo.singular_values,loc="right",title="Singular values")

    subplot(312)
    for i = 1:Nb
        p = basisinfo.svdbasis.projectors[i,:]
        plot(p ./ norm(p))
    end
    xlabel("Sample number")
    ylabel("Projectors (scaled to norm=1)")

    subplot(313)
    noise_std = √(basisinfo.svdbasis.noise_result.autocorr[1])
    normalized_sorted_residuals = sort(basisinfo.std_residuals)/noise_std
    Ntrain = length(normalized_sorted_residuals)
    a=normalized_sorted_residuals[1]
    b=max(1.5*a, normalized_sorted_residuals[ceil(Int, Ntrain*0.9)])
    plot(normalized_sorted_residuals, range(0, stop=1, length=length(normalized_sorted_residuals)))
    xlim(a,b)
    ylim(0,1)
    xlabel("(Residual std)/(Noise std)")
    ylabel("Frac. training pulses w/ lower residual")
    grid(true)
end


function plot_example_pulses(basisinfo)
    for i = 1:ceil(Int,length(basisinfo.percentiles_of_sample_pulses)/9)
        r = (1:9) .+ (i-1)*9
        figure(figsize=(10,10))
        subplot(311)
        artists=plot(basisinfo.example_pulses[:,r])
        legend(artists,basisinfo.percentiles_of_sample_pulses[r],loc="right",title="Percentile of residual std")
        xlabel("Sample number")
        ylabel("Measured pulses")
        titleme(basisinfo)

        subplot(312)
        model_pulses = basisinfo.svdbasis.basis*basisinfo.svdbasis.projectors*basisinfo.example_pulses[:,r]
        residuals = basisinfo.example_pulses[:,r]-model_pulses
        noise_std = √(basisinfo.svdbasis.noise_result.autocorr[1])
        artists=plot(residuals)
        std_residual_normalized = Float32.(std(residuals, dims=1)'[:]/noise_std)
        std_residual_normalized_from_training = basisinfo.std_residuals_of_example_pulses/noise_std
        legend(artists, std_residual_normalized, loc="right", title="std dev/noise std dev")
        xlabel("Sample number")
        ylabel("Residuals (measured-model)")
        ylim(-7*median(std_residual_normalized)*noise_std,7*median(std_residual_normalized)*noise_std)

        subplot(313)
        artists = plot(model_pulses)
        xlabel("Sample number")
        ylabel("Model pulses")
    end
end


function write_all_plots_to_pdf(pdffile)
    for i in plt.get_fignums()
        figure(i)
        pdffile.savefig(i)
        close(i)
    end
end

function main(parsed_args)
    h5 = h5open(parsed_args["basisfile"],"r")
    pdffile = pdf.PdfPages(parsed_args["outputfile"])
    channelnames = string.(sort(parse.(Int,names(h5))))
    for name in channelnames
        println("plotting channel $name")
        channel = parse(Int,name)
        basisinfo = Pope.hdf5load(Pope.SVDBasisWithCreationInfo,h5["$name"])
        plot_model_and_residuals(basisinfo)
        plot_example_pulses(basisinfo)
        write_all_plots_to_pdf(pdffile)
    end
    close(h5)
    pdffile.close()
    plt.close("all")
end

main(parsed_args)
