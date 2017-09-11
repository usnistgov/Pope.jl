#!/usr/bin/env python
import numpy as np
# import pylab as plt
import mass
from os import path
import os
# import shutil
# import traceback, sys
# from matplotlib.backends.backend_pdf import PdfPages
# import datetime
# import pickle
# import lmfit
import time
# import parse_logs
# from mono_calibration_transfer import *
# import collections
import h5py
import argparse

import sys

def query_yes_no(question, default="yes"):
    """Ask a yes/no question via raw_input() and return their answer.

    "question" is a string that is presented to the user.
    "default" is the presumed answer if the user just hits <Enter>.
        It must be "yes" (the default), "no" or None (meaning
        an answer is required of the user).

    The "answer" return value is True for "yes" or False for "no".
    """
    valid = {"yes": True, "y": True, "ye": True,
             "no": False, "n": False}
    if default is None:
        prompt = " [y/n] "
    elif default == "yes":
        prompt = " [Y/n] "
    elif default == "no":
        prompt = " [y/N] "
    else:
        raise ValueError("invalid default answer: '%s'" % default)

    while True:
        sys.stdout.write(question + prompt)
        choice = raw_input().lower()
        if default is not None and choice == '':
            return valid[default]
        elif choice in valid:
            return valid[choice]
        else:
            sys.stdout.write("Please respond with 'yes' or 'no' "
                             "(or 'y' or 'n').\n")

def estimate_peak_index_ds(ds):
    first, end, data = ds.pulse_records.datafile.read_segment(0)
    peakinds = data.argmax(axis=1)
    peakind = np.argmax(np.bincount(peakinds)) # find the mode peak index (most frequent peak index)
    mad = np.median(np.abs(peakinds-peakind))
    return peakind, mad

def estimate_peak_time_microsec_ds(ds):
    peakind_abs, mad = estimate_peak_index_ds(ds)
    peakind_rel = peakind_abs-ds.nPresamples
    # add the median absolute deviation (or 1) to the peakind to avoid cutting low energy pulses that peak earlier
    peakind = peakind_rel+max(1,mad)
    return peakind*ds.timebase*1e6

def calc_cuts_from_noise(self, nsigma_max_deriv=7, nsigma_pt_rms=7):
    """
    calc_cuts_from_noise(self, nsigma=7)
    Use noise files to calculate ranges that encompass nsigma sigmas worth of deviation in the
    pretrigger mean and max deriv. Uses median absolute deviation to be robust to outliers.
    return a mass.core.controller.AnalysisControl() object with cuts defined for pretrigger_rms and postpeak_deriv
    """

    max_deriv = np.zeros(self.noise_records.nPulses)
    pretrigger_rms = np.zeros(self.noise_records.nPulses)
    for _first_pnum, _end_pnum, _seg_num, data_seg in self.noise_records.datafile.iter_segments():
        max_deriv[_first_pnum:_end_pnum]=mass.analysis_algorithms.compute_max_deriv(data_seg,ignore_leading=0)
        pretrigger_rms[_first_pnum:_end_pnum]=data_seg[:,:self.nPresamples].std(axis=1)

    md_med = np.median(max_deriv)
    md_mad = np.median(np.abs(max_deriv-md_med))
    pt_med = np.median(pretrigger_rms)
    pt_mad = np.median(np.abs(pretrigger_rms-pt_med))
    # for gausssian distributed data sigma = 1.4826*median_absolute_deviation
    # so if we want 5 sigma deviation, we want 5*1.4826*mad
    nmad_max_deriv = nsigma_max_deriv*1.4826
    nmad_pt_rms    = nsigma_pt_rms*1.4826
    # md_min = max(0.0,md_med-md_mad*nmad_max_deriv)
    md_min = -np.inf
    md_max = md_med+md_mad*nmad_max_deriv
    # pt_min = pt_med-pt_mad*nmad_pt_rms
    pt_min = 0.0 # lower limit on pretrigger mean is not normally used, and when I tried I found many channels failing with lots cut due to this. I guess the noise had reduced over time.
    pt_max = max(0.0,pt_med+pt_mad*nmad_pt_rms)

    cuts = mass.core.controller.AnalysisControl(
        pretrigger_rms=(pt_min, pt_max),
        postpeak_deriv=(md_min, md_max),
    )
    return cuts

def write_preknowledge_data(filename,data,exclude_channels):
    with h5py.File(filename,"w") as h5:
        for ds in data:
            g = h5.require_group("chan%g"%ds.channum)
            write_preknowledge_ds(g,ds)
    return filename

def write_preknowledge_ds(g,ds):
        g.require_group("physical")
        # g["physical"]["x_um_from_array_center"]=0
        # g["physical"]["y_um_from_array_center"]=0
        # g["physical"]["collimator open area"]=0
        g["physical"]["frametime"]=ds.timebase
        g["physical"]["number_of_rows"]=ds.number_of_rows
        g["physical"]["number_of_columns"]=ds.number_of_columns

        g.require_group("trigger")
        g["trigger"]["nsamples"]=ds.nSamples
        g["trigger"]["npresamples"]=ds.nPresamples
        # g["trigger"]["avoid_edge"]=True
        # g["trigger"]["type"]="edge"
        # g["trigger"]["level_specify_units_in_name"]=0.1

        g.require_group("filter")
        g["filter"]["data_file_used_to_generate_filters"]=ds.filename
        g["filter"]["values"] = ds.filter.filt_noconst
        g["filter"]["values_at"] = ds.filter.filt_aterms.reshape((-1,))
        if ds.filter.f_3db is None:
            g["filter"]["f3db"] = 100000000.0 # its none, want a float, justmake it obviously odd
        else:
            g["filter"]["f3db"] = ds.filter.f_3db
        g["filter"]["average_pulse"] = ds.filter.avg_signal
        # g["filter"]["average_pulse_energy_eV"]=5989.0
        g["filter"]["description"] = "noconst"
        g["filter"]["shift_threshold"] = int(round(4.3*np.median(ds.p_pretrig_rms[ds.good()])))

        g.require_group("summarize")
        g["summarize"]["peak_index"]=ds.peakindex1

        g.require_group("cuts")
        for (k,v) in ds.usedcuts.cuts_prm.iteritems():
            if v is not None:
                g["cuts"][k] = np.array([v[0],v[1]])

        g["analysis_type"]="mass compatible feb 2017"

parser = argparse.ArgumentParser(description='Create a prekowledge file for Pope.jl',
    epilog="""For each channel, calcuates the peak index based on the mode plus median absolute deviation in the first segment of the pulse_file.
    Then summarizes data. Thenit calculated a pretrigger_rms and post_peak deriv cut based on applying thos alogritms to a noise file and choosing
    7 sigma cuts (actually uses median absolute deviation * a scale factor instead of std to calcualte sigma). Then it applies cuts,
    calculates average pulse, and computes filters. And writes info to a preknowledge file.""")
parser.add_argument('pulse_file', help='name of the pulse containing ljh file to use to make preknowledge')
parser.add_argument('noise_file', help='name of the noise containing ljh file to use to make preknowledge')
parser.add_argument('--base', help="path.join this to both pulse_file and noise_file",default="")
parser.add_argument('out', help="directory to write the output file",default=".",nargs="?")
parser.add_argument('basename', help="first letters of the prekowledge filename", default="pk",nargs="?")
parser.add_argument('--maxchannels', help="maximum number of channels to process (mostly just for testing faster)",default="240",type=int)
parser.add_argument('--nsigma_max_deriv', help="the larger this value is, the more pulses will pass the max_deriv cut", default="7", type=int)
parser.add_argument('--nsigma_pt_rms', help="the larger this value is, the more pulses will pass the pretrigger_rms cut", default="7", type=int)
parser.add_argument('--exclude_channels', help="comma seperated list of channesl to exclude", default="", nargs=1)
parser.add_argument('--quality_report',help="include this to generate a pdf with info on each channel",action='store_true')
parser.add_argument('--fulloutputpath',help="provide the full output path to the output preknowledge file, ingores out and basename", default="", type=str)
parser.add_argument('--noprompt',help="skip the sanity check prompt (for automated use)",action='store_true')
parser.add_argument('--f3db',help="set f3db for filters (default 20000 hz)",default="20000",type=float)
parser.add_argument('--dont_popeonceafter',help="supply to avoid running popeonce with the new preknowledge, on pulse_file",action="store_true")
parser.add_argument('--apply_filters',help="for testing this will apply filters with mass, this has no effect on the preknowledge file",action="store_true")
args = vars(parser.parse_args())
for (k,v) in args.iteritems():
    print("%s: %s"%(k, v))

dir_p = args["pulse_file"]
dir_n = args["noise_file"]
outdir = args["out"]
if not path.isdir(outdir): raise ValueError("%s is not a directory"%outdir)
# single file stuff
dir_base=args["base"]
forceNew = True
maxnchans = args["maxchannels"]
nsigma_max_deriv = args["nsigma_max_deriv"]
nsigma_pt_rms = args["nsigma_pt_rms"]
if not args["exclude_channels"]=="":
    try:
        exclude_channels = map(int,args["exclude_channels"][0].rstrip().split(","))
    except:
        print(str(args["exclude_channels"])+" not a comma seperated list of ints")
        print("try something like --exclude_channels=1,2,6")
        sys.exit()
else:
    exclude_channels=[]


available_chans = mass.ljh_util.ljh_get_channels_both(path.join(dir_base, dir_p), path.join(dir_base, dir_n))
for chan in exclude_channels:
    available_chans.remove(chan)
if len(available_chans) == 0:
    raise ValueError("no channels have both noise and pulse data")
chan_nums = available_chans[:maxnchans]
pulse_files = mass.ljh_util.ljh_chan_names(path.join(dir_base, dir_p), chan_nums)
noise_files = mass.ljh_util.ljh_chan_names(path.join(dir_base, dir_n), chan_nums)

f=mass.LJHFile(pulse_files[0])
pkfilename0 = args["basename"]+"_%gx%g_%gsamples.preknowledge"%(f.number_of_columns, f.number_of_rows, f.nSamples)
pkfilename = path.join(args["out"],pkfilename0)
if args["fulloutputpath"] != "":
    pkfilename=args["fulloutputpath"]
    print("Output name determined solely by --fulloutputpath argument.")

#   popeonce.jl <ljhpath> <preknowledge> <output>
def make_pope_hdf5_name(ljhname):
    return mass.ljh_util.ljh_basename_channum(ljhname)[0]+".ljh_pope.hdf5"
assert(make_pope_hdf5_name("/a/b/c/c_chan1.ljh")=="/a/b/c/c.ljh_pope.hdf5")
pope_hdf5_name = make_pope_hdf5_name(pulse_files[0])
bdir = path.dirname(os.path.realpath(__file__))
popeoncecommand = [path.join(bdir,"popeonce.jl"),pulse_files[0],pkfilename,pope_hdf5_name]

print("nsigma_max_deriv %0.2f, nsigma_pt_rms %0.2f"%(nsigma_max_deriv, nsigma_pt_rms))
print("Channels: %s"%chan_nums)
print("Excluded Channels: %s"%exclude_channels)
print("First pulse file: %s"%pulse_files[0])
print("First noise file: %s"%noise_files[0])
if not args["dont_popeonceafter"]:
    print("Will run popeonce after with this command:")
    print(popeoncecommand)

print("Output name: %s"%pkfilename)
if path.isfile(pkfilename):
    print("%s already exists, manually move or remove it if you want to use that name"%pkfilename)
    sys.exit()
if not args["noprompt"]:
    keepgoing = query_yes_no("Do this info look right so far?")
    if not keepgoing:
        print("aborting")
        sys.exit()

hdf5_filename, hdf5_noisefilename = "make_preknowledge_temp.hdf5", "make_preknowledge_noise_temp.hdf5"
if path.isfile(hdf5_filename):
    os.remove(hdf5_filename)
if path.isfile(hdf5_noisefilename):
    os.remove(hdf5_noisefilename)
data = mass.TESGroup(pulse_files, noise_files, hdf5_filename=hdf5_filename, hdf5_noisefilename=hdf5_noisefilename)
# data.updater = mass.utilities.NullUpdater
data.set_chan_good(data.why_chan_bad.keys())
fracuncut = []
nuncut = []
chnums = []
for ds in data:
    peak_time_microsec = estimate_peak_time_microsec_ds(ds)
    ds.peakindex1 = int(1e-6*peak_time_microsec/ds.timebase)+ds.nPresamples+1 # peak index from first 1 based index
    ds.summarize_data(peak_time_microsec, forceNew=forceNew)
    ds.usedcuts = calc_cuts_from_noise(ds,nsigma_max_deriv=nsigma_max_deriv, nsigma_pt_rms=nsigma_pt_rms)
    ds.apply_cuts(ds.usedcuts, clear=True) # forceNew is true by default
    fracuncut.append(ds.good().sum()/float(ds.nPulses))
    nuncut.append(ds.good().sum())
    chnums.append(ds.channum)

print("Mean fraction of uncut pulses: %0.3f"%np.mean(fracuncut))
print("Std deviation of fraction of uncut pulses: %0.3f"%np.std(fracuncut))
print("Mean number of uncut pulses: %0.1f"%np.mean(nuncut))
print("Channels with less than 90% of pulses uncut or less than 100 puluses uncut: ")
inds = np.where(np.logical_or(np.array(fracuncut)<0.9, np.array(nuncut)<100))[0]
indsall = np.arange(len(nuncut))
s=""
for i in inds[np.argsort(np.array(fracuncut)[inds])]:
    ch = chnums[i]
    ds = data.channel[ch]
    npulses = ds.nPulses
    s+="Ch %g: %g/%g=%0.2f, "%(ch, nuncut[i], npulses, fracuncut[i])
if not s=="": print(s[:-2])
# keepgoing = query_yes_no("Do these cut stats look ok?")
# if not keepgoing:
#     print("aborting")
#     sys.exit()


data.avg_pulses_auto_masks(forceNew=forceNew)  # creates masks and compute average pulses
data.compute_filters(f_3db=args["f3db"], forceNew=forceNew)
if args["apply_filters"]:
    print("applying filters per command line argument")
    data.filter_data()


print("writing preknowledge file")
write_preknowledge_data(pkfilename,data,exclude_channels)
print("wrote: %s"%pkfilename)

if args["quality_report"]:
    import quality_check
    print("writing quality report")
    quality_check.write_pdf_report(data,pkfilename+"_quality.pdf",nsigma_pt_rms, nsigma_max_deriv,noise_files[0],pulse_files[0])
    print("done writing quality report")


if not args["dont_popeonceafter"]:
    import subprocess
    print("Running the following:")
    print(popeoncecommand)
    proc=subprocess.Popen(popeoncecommand)
    proc.wait()
else:
    print("not running popeonce after")
