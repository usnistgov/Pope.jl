from matplotlib.backends.backend_pdf import PdfPages
import scipy.optimize
import datetime
import numpy as np
import pylab as plt

def normalized_average_pulse(ds):
    return ds.average_pulse[:]/np.amax(ds.average_pulse[:])


def channels_with_odd_average_pulse(data,nsigma=5):
    channums = np.array([ds.channum for ds in data])
    norm_avg_pulses = np.zeros((ds.nSamples, len(channums)))
    for i,ds in enumerate(data):
        norm_avg_pulses[:,i]=normalized_average_pulse(ds)

    avg_avg_pulse = np.mean(norm_avg_pulses,axis=1)
    resid = norm_avg_pulses.T-avg_avg_pulse
    weighted_resid = resid/avg_avg_pulse
    std_resid = np.std(resid[:,ds.nPresamples:],axis=1)
    std_weight_resid = np.std(weighted_resid[:,ds.nPresamples:],axis=1)
    std_resid = std_weight_resid
    mad_std_resid = np.median(np.abs(std_resid-np.median(std_resid)))
    med_std_resid = np.median(std_resid)
    sigma = mad_std_resid*1.4826
    keep_below = med_std_resid+nsigma*sigma

    bad_inds = np.where(std_resid>keep_below)[0]
    # plt.figure()
    # plt.plot(std_resid,".")
    # plt.plot(bad_inds, std_resid[bad_inds],".")
    bad_chans = [channums[i] for i in bad_inds]
    return bad_chans

def plot_odd_average_pulses(data):
    bad_chans = channels_with_odd_average_pulse(data)
    plt.figure()
    for ds in data:
        if ds.channum in bad_chans:
            plt.plot(normalized_average_pulse(ds), label=ds.channum)
        else:
            plt.plot(normalized_average_pulse(ds),"k",label=None)
    plt.yscale("log")
    plt.ylim(1e-4,1)
    if len(bad_chans)>0:
        plt.legend(loc="best")
    plt.xlabel("sample number")
    plt.ylabel("signal size (normalized)")



def two_exp_model(t, amp,tau1, tau2,t0):
    t0=0
    tau1=float(tau1)
    tau2=float(tau2)
    if tau1==tau2:
        y = (t-t0)*np.exp(-(t-t0)/tau1)
    else:
        y = -np.exp(-(t-t0)/tau1)+np.exp(-(t-t0)/tau2)
    m = np.amax(y)
    if m==0:
        return y
    else:
        return amp*y/m

def two_exp_fit(ds):
    guess = [1,50,51,-0.5]
    ydata = ds.average_pulse[ds.nPresamples+1:]
    xdata = np.arange(len(ydata))
    popt, pcov = scipy.optimize.curve_fit(two_exp_model, xdata, ydata, guess, bounds = ([0,1,1,-2],[1e6,1e5,1e5,2]))
    sigma = np.array([np.sqrt(pcov[i,i]) for i in np.arange(len(popt))])
    ydata = np.hstack((np.zeros(ds.nSamples-len(ydata)),two_exp_model(xdata, *popt)))
    return popt, sigma, ydata



def midpoints(x):
    return 0.5*(x[1:]+x[:-1])

def plot_traces(ds):
    plt.figure(figsize=(18,10))
    ax1=plt.subplot(231)
    ax2=plt.subplot(232)
    ax3=plt.subplot(233)
    ds.plot_traces(np.where(ds.good())[0][:10], axis=ax1, pulse_summary=False)
    inds_pt = np.where(np.logical_and(ds.bad("pretrigger_rms"),ds.good("postpeak_deriv")))[0][:10]
    ds.plot_traces(inds_pt, axis=ax2, pulse_summary=False)
    inds_md = np.where(np.logical_and(ds.bad("postpeak_deriv"),ds.good("pretrigger_rms")))[0][:10]
    ds.plot_traces(inds_md, axis=ax3, pulse_summary=False)
    ax1.set_title("Channel %g: uncut pulses"%ds.channum)
    ax2.set_title("cut by pretrigger_rms only")
    ax3.set_title("cut by postpeak_deriv only")

    colors = [line.get_color() for line in ax1.lines]

    ax4=plt.subplot(234)
    plt.plot(ds.average_pulse,label="average pulse")
    try:
        popt, sigma,ydata = two_exp_fit(ds)
        amp, tau1, tau2, t0 = popt
        damp, dtau1, dtau2, dt0 = sigma
        plt.plot(ydata, label="tau1=%0.1f+/-%0.1f\ntau2=%0.1f+/-%0.1f\ntau in samples\n%0.2f us/sample"%(tau1, dtau1, tau2, dtau2,ds.timebase*1e6))
    except:
        plt.plot(0,0,label="fit failed")
    plt.xlabel("sample number")
    plt.ylabel("signal height")
    plt.title("Channel %g: average pulse"%(ds.channum))
    plt.legend(loc="best")

    ax5=plt.subplot(235)
    pt_lo,pt_hi=ds.usedcuts.cuts_prm["pretrigger_rms"]
    i_pt = ds.p_pretrig_rms[:][inds_pt]
    bin_edges_uncut = np.arange(0,pt_hi*1.03,pt_hi/50.)
    bin_edges_cut    = np.arange(pt_hi,4*pt_hi,pt_hi/50.)
    counts_uncut,_ = np.histogram(ds.p_pretrig_rms, bin_edges_uncut)
    counts_cut,_ = np.histogram(ds.p_pretrig_rms, bin_edges_cut)
    plt.plot(midpoints(bin_edges_uncut), counts_uncut, drawstyle="steps-mid",label="uncut")
    plt.plot(midpoints(bin_edges_cut), counts_cut, drawstyle="steps-mid",label="cut")
    plt.xlabel("pretrigger_rms")
    plt.ylabel("occurences")
    plt.legend(loc="best")
    plt.annotate("%0.2f"%pt_hi, (pt_hi, counts_uncut[-1]))
    i_counts = np.interp(i_pt, np.hstack((midpoints(bin_edges_uncut), midpoints(bin_edges_cut))), np.hstack((counts_uncut, counts_cut)))
    plt.scatter(i_pt, i_counts, marker="o",color=colors)
    plt.xlim(0,4*pt_hi)

    ax6=plt.subplot(236)
    md_lo,md_hi=ds.usedcuts.cuts_prm["postpeak_deriv"]
    i_md = ds.p_postpeak_deriv[:][inds_md]
    bin_edges_uncut = np.arange(0,md_hi*1.03,md_hi/50.)
    bin_edges_cut    = np.arange(md_hi,4*md_hi,md_hi/50.)
    counts_uncut,_ = np.histogram(ds.p_postpeak_deriv, bin_edges_uncut)
    counts_cut,_ = np.histogram(ds.p_postpeak_deriv, bin_edges_cut)
    plt.plot(midpoints(bin_edges_uncut), counts_uncut, drawstyle="steps-mid",label="uncut")
    plt.plot(midpoints(bin_edges_cut), counts_cut, drawstyle="steps-mid",label="cut")
    plt.xlabel("postpeak_deriv")
    plt.ylabel("occurences")
    plt.legend(loc="best")
    plt.annotate("%0.2f"%md_hi, (md_hi, counts_uncut[-1]))
    i_counts = np.interp(i_md, np.hstack((midpoints(bin_edges_uncut), midpoints(bin_edges_cut))), np.hstack((counts_uncut, counts_cut)))
    plt.scatter(i_md, i_counts, marker="o",color=colors)
    plt.xlim(0, 4*md_hi)


def write_pdf_report(data,fname="pope_quality_report.pdf", maxchan=240):
    print("writing pdf report")
    with PdfPages(fname) as pdf:
        d = pdf.infodict()
        d['Title'] = 'Pope channel report'
        d['Author'] = 'Pope.jl software'
        d['CreationDate'] = datetime.datetime.today()
        d['ModDate'] = datetime.datetime.today()
        plot_odd_average_pulses(data)
        pdf.savefig()
        plt.close()
        channums = np.array([ds.channum for ds in data])
        count = 0
        for (i,ds) in enumerate(data):
            if count>=maxchan:
                break
            count+=1
            print("pdf %g/%g"%(i+1, min(len(channums), maxchan)))
            plot_traces(ds)
            pdf.savefig()  # saves the current figure into a pdf page
            plt.close()
