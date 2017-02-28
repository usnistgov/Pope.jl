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
            channum = int(k[4:-1])
            if "channum" not in v.attrs: v.attrs["channum"]=channum
            if "noise_filename" not in v.attrs: v.attrs["noise_filename"]="analyzed by pope, used preknowledge"
            if "npulses" not in v.attrs: v.attrs["npulses"]=len(v["filt_value"])


def open_pope_hdf5(filename):
    prep_pope_hdf5_for_mass(filename)
    data = mass.TESGroupHDF5(filename)



if __name__ == "__main__":
    print sys.argv
    open_pope_hdf5(sys.argv[1])
