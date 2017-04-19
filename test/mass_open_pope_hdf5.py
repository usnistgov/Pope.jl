# This file exist to analyze an ljh file to provide a valid preknowlege file
# and analysis results for testing Pope.jl

import mass
import numpy as np
import h5py
import os
import sys
import shutil

def open_pope_hdf5_only(filename):
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
    return data

def open_pope_hdf5_with_ljh(ljhfilename, noisefilename, hdf5_filename):
    data = mass.TESGroup([ljhfilename], [noisefilename], hdf5_filename=hdf5_filename)
    cuts=mass.controller.AnalysisControl(
            pretrigger_rms=(None,30.),    # A cut against "big tails" from prior pulses
            postpeak_deriv=(None, 20),
            timestamp_diff_sec=(0.020, None)
            )
    data.apply_cuts(cuts)
    ds = data.first_good_dataset
    data.calibrate("p_filt_value",["MnKAlpha"])
    assert(ds.channum==13)
    assert(ds.nPulses==3038)


if __name__ == "__main__":
    print sys.argv # arguments should be: hdf5_filename
    hdf5_filename = sys.argv[1]
    # open file with ljh files
    # make a copy of the ljh file first, so that it doesn't affect the next test without ljh files
    fname = os.path.expanduser("~/.julia/v0.5/ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh")
    nfname = os.path.expanduser("~/.julia/v0.5/ReferenceMicrocalFiles/ljh/20150707_C_chan13.noi")
    hdf5_filename_copy = hdf5_filename+"copy"
    shutil.copy(hdf5_filename,hdf5_filename_copy)
    data0 = open_pope_hdf5_with_ljh(fname, nfname, hdf5_filename_copy)

    #open file without ljh files
    data1 = open_pope_hdf5_only(hdf5_filename)
    print data1
