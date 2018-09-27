#!/usr/bin/env julia
using ArgParse
s = ArgParseSettings()
@add_arg_table s begin
    "basisfile"
        help = "name of the HDF5 containing basis and creation info"
        required = true
    "--outputfile","-o"
        help = "the output pdf file path, otherwise it will make up a name"

end
using PyCall, PyPlot, HDF5, Pope
parsed_args = parse_args(ARGS, s)
if parsed_args["outputfile"]==nothing
    parsed_args["outputfile"] = Pope.outputname(parsed_args["basisfile"],"plots","pdf")
end
display(parsed_args);println()
@pyimport matplotlib.backends.backend_pdf as pdf

function plot_model_and_residuals(basisinfo)
    figure(figsize=(10,10))
    subplot(311)
    artists=plot(basisinfo.svdbasis.basis)
    xlabel("sample number")
    ylabel("model components")
    title("ch $(basisinfo.channel_number)
    noise_file: $(basename(basisinfo.noise_model_file))
    pulse_file: $(basename(basisinfo.pulse_file))")
    legend(artists, basisinfo.singular_values,loc="right",title="singular values")
    subplot(312)
    plot(basisinfo.svdbasis.projectors')
    xlabel("sample number")
    ylabel("projectors (currently equal to basis)")
    subplot(313)
    noise_std = √(basisinfo.svdbasis.noise_result.autocorr[1])
    normalized_sorted_residuals = sort(basisinfo.std_residuals)/noise_std
    a=normalized_sorted_residuals[1]
    b=max(1.5*a,median(normalized_sorted_residuals))
    plot(normalized_sorted_residuals,linspace(0,1,length(normalized_sorted_residuals)))
    xlim(a,b)
    ylim(0,1)
    xlabel("(residual std)/(noise std)")
    ylabel("fraction of training pulses with lower residual")
    grid(true)
end
function plot_example_pulses(basisinfo)
    for i = 1:ceil(Int,length(basisinfo.percentiles_of_sample_pulses)/9)
        r=(1:9)+(i-1)*9
        figure(figsize=(10,10))
        subplot(311)
        artists=plot(basisinfo.example_pulses[:,r])
        legend(artists,basisinfo.percentiles_of_sample_pulses[r],loc="right",title="residual std percentile")
        xlabel("sample number")
        ylabel("actual pulses")
        title("ch $(basisinfo.channel_number)
        noise_file: $(basename(basisinfo.noise_model_file))
        pulse_file: $(basename(basisinfo.pulse_file))")
        subplot(312)
        model_pulses = basisinfo.svdbasis.basis*basisinfo.svdbasis.projectors*basisinfo.example_pulses[:,r]
        residuals = basisinfo.example_pulses[:,r]-model_pulses
        noise_std = √(basisinfo.svdbasis.noise_result.autocorr[1])
        artists=plot(residuals)
        std_residual_normalized = Float32.(std(residuals,1)'[:]/noise_std)
        std_residual_normalized_from_training = basisinfo.std_residuals_of_example_pulses/noise_std
        legend(artists,std_residual_normalized, loc="right",title="standard deviation/noise std")
        xlabel("sample number")
        ylabel("actual-model (aka residuals)")
        ylim(-7*median(std_residual_normalized)*noise_std,7*median(std_residual_normalized)*noise_std)
        subplot(313)
        artists = plot(model_pulses)
        xlabel("sample number")
        ylabel("model pulses")
    end
end
function write_all_plots_to_pdf(pdffile)
    for i in plt[:get_fignums]()
        figure(i)
        pdffile[:savefig](i)
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
    pdffile[:close]()
    plt[:close]("all")
end

main(parsed_args)
