#!/usr/bin/env python
import numpy as np
import pylab as plt
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

def calc_cuts_from_noise(self, nsigma=7):
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
    nmad = nsigma*1.4826
    md_min = max(0.0,md_med-md_mad*nmad)
    md_max = md_med+md_mad*nmad
    pt_min = pt_med-pt_mad*nmad
    pt_max = max(0.0,pt_med+pt_mad*nmad)

    cuts = mass.core.controller.AnalysisControl(
        pretrigger_rms=(pt_min, pt_max),
        postpeak_deriv=(md_min, md_max),
    )
    return cuts

def write_preknowledge_data(filename,data):
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
            g["filter"]["f3db"] = 100000000.0 # its none, want a float
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

        # g.require_group("calibration")
        # g["calibration"].require_group("p_filt_value")
        # g["calibration"]["p_filt_value"]["data_file_used"] = ds.filename
        # g["calibration"]["p_filt_value"]["lines_used"] = "MnKAlpha, MnKBeta"
        # g["calibration"]["p_filt_value"]["energies"] = [1,2]
        # g["calibration"]["p_filt_value"]["ph"] = [1,2]
        # g["calibration"]["p_filt_value"]["de"] = [1,2]
        # g["calibration"]["p_filt_value"]["dph"] = [1,2]

        g["analysis_type"]="mass compatible feb 2017"

parser = argparse.ArgumentParser(description='Create a prekowledge file for Pope.jl',
    epilog="""For each channel, calcuates the peak index based on the mode plus median absolute deviation in the first segment of the pulse_file.
    Then summarizes data. Thenit calculated a pretrigger_rms and post_peak deriv cut based on applying thos alogritms to a noise file and choosing
    7 sigma cuts (actually uses median absolute deviation * a scale factor instead of std to calcualte sigma). Then it applies cuts,
    calculates average pulse, and computes filters. And writes info to a prekoledge file.""")
parser.add_argument('pulse_file', help='name of the pulse containing ljh file to use to make preknowledge')
parser.add_argument('noise_file', help='name of the noise containing ljh file to use to make preknowledge')
parser.add_argument('--base', help="path.join this to both pulse_file and noise_file",default="")
parser.add_argument('out', help="directory to write the output file",default=".",nargs="?")
parser.add_argument('basename', help="first letters of the prekowledge filename", default="pk",nargs="?")
parser.add_argument('--maxchannels', help="maximum number of channels to process (mostly just for testing faster)",default="240",type=int)

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

available_chans = mass.ljh_get_channels_both(path.join(dir_base, dir_p), path.join(dir_base, dir_n))
if len(available_chans) == 0:
    raise ValueError("no channels have both noise and pulse data")
chan_nums = available_chans[:maxnchans]
pulse_files = mass.ljh_chan_names(path.join(dir_base, dir_p), chan_nums)
noise_files = mass.ljh_chan_names(path.join(dir_base, dir_n), chan_nums)

print("Channels: %s"%chan_nums)
print("First pulse file: %s"%pulse_files[0])
print("First noise file: %s"%noise_files[0])
f=mass.LJHFile(pulse_files[0])
pkfilename0 = args["basename"]+"_%gx%g_%gsamples.preknowledge"%(f.number_of_columns, f.number_of_rows, f.nSamples)
pkfilename = path.join(args["out"],pkfilename0)
print("Output name: %s"%pkfilename)
if path.isfile(pkfilename):
    print("%s already exists, manually move or remove it if you want to use that name"%pkfilename)
    sys.exit()
keepgoing = query_yes_no("Do this info look right so far?")
if not keepgoing:
    print("aborting")
    sys.exit()

data = mass.TESGroup(pulse_files, noise_files)
# data.updater = mass.utilities.NullUpdater
data.set_chan_good(data.why_chan_bad.keys())
for ds in data:
    peak_time_microsec = estimate_peak_time_microsec_ds(ds)
    ds.peakindex1 = int(1e-6*peak_time_microsec/ds.timebase)+ds.nPresamples+1 # peak index from first 1 based index
    ds.summarize_data(peak_time_microsec, forceNew=forceNew)
    ds.usedcuts = calc_cuts_from_noise(ds,nsigma=7)
    ds.apply_cuts(ds.usedcuts, clear=True) # forceNew is true by default
data.avg_pulses_auto_masks(forceNew=forceNew)  # creates masks and compute average pulses
data.compute_filters(f_3db=20000.0, forceNew=forceNew)



write_preknowledge_data(pkfilename,data)
print("wrote: %s"%pkfilename)
