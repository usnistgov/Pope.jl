# This file exist to analyze an ljh file to provide a valid preknowlege file
# and analysis results for testing Pope.jl

import mass
import numpy as np
import h5py

fname = "~/.julia/v0.5/ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh"
nfname = "~/.julia/v0.5/ReferenceMicrocalFiles/ljh/20150707_C_chan13.noi"
hdf5_filename = "~/.julia/v0.5/Pope/test/mass.h5"
preknowledge_filename = "~/.julia/v0.5/Pope/test/preknowledge.h5"

def mass_analyze(fname, nfname, hdf5_filename, preknowledge_filename):

    data = mass.TESGroup([fname],[nfname], hdf5_filename=None)
    data.summarize_data(peak_time_microsec=220.0)
    ds = data.first_good_dataset
    cuts=mass.controller.AnalysisControl(
            pretrigger_rms=(None,30.),    # A cut against "big tails" from prior pulses
            postpeak_deriv=(None, 20),
            timestamp_diff_sec=(0.020, None)
            )
    data.apply_cuts(cuts)
    data.compute_filters()
    data.filter_data()
    # ds.calibrate("p_filt_value",cal_lines)

    with h5py.File(preknowledge_filename,"w") as h5:
        g = h5["chan%g"%ds.channum]
        g["filter"]["data_file_used"]=ds.filename
        g["filter"]["values"] = ds.filter.filt_noconst
        g["filter"]["values_at"] = ds.filter.filt_aterms
        g["filter"]["f3db"] = 100000000.0 # its none, want a float
        g["filter"]["average_pulse"] = ds.filters.avg_signal
        g["filter"]["average_pulse_energy_eV"]=5989.0
        g["filter"]["description"] = "noconst"

        g["cuts"]["pretrigger_rms"] = [0.0,30.0]
        g["cuts"]["postpeak_deriv"] = [0.0,20.0]

        g["calibration"]["p_filt_value"]["data_file_used"] = ds.filename
        g["calibration"]["p_filt_value"]["lines_used"] = "MnKAlpha, MnKBeta"
        g["calibration"]["p_filt_value"]["energies"] = [1,2]
        g["calibration"]["p_filt_value"]["ph"] = [1,2]
        g["calibration"]["p_filt_value"]["de"] = [1,2]
        g["calibration"]["p_filt_value"]["dph"] = [1,2]
