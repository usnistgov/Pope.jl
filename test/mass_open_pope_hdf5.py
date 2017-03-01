# This file exist to analyze an ljh file to provide a valid preknowlege file
# and analysis results for testing Pope.jl

import mass
import numpy as np
import h5py
import os
import sys


def prep_pope_hdf5_for_mass(filename):
    with h5py.File(filename) as h5:
        for k,v in h5.iteritems():
            print k,v
            if not k.startswith("chan"): continue
            channum = int(k[4:])
            if "channum" not in v.attrs: v.attrs["channum"]=channum
            if "noise_filename" not in v.attrs: v.attrs["noise_filename"]="analyzed by pope, used preknowledge"
            if "npulses" not in v.attrs: v.attrs["npulses"]=len(v["filt_value"])


def open_pope_hdf5(filename):
    prep_pope_hdf5_for_mass(filename)
    data = mass.TESGroupHDF5(filename)
    cuts=mass.controller.AnalysisControl(
            pretrigger_rms=(None,30.),    # A cut against "big tails" from prior pulses
            postpeak_deriv=(None, 20),
            timestamp_diff_sec=(0.020, None)
            )
    data.apply_cuts(cuts)
    data.calibrate("p_filt_value",["MnKAlpha"])
    ds = data.first_good_dataset
    assert(ds.channum==13)
    assert(ds.nPulses==3038)
    print("filename",ds.filename)
    return data


if __name__ == "__main__":
    print sys.argv
    data = open_pope_hdf5(sys.argv[1])
    print data
