# This file exist to analyze an ljh file to provide a valid preknowlege file
# and analysis results for testing Pope.jl

import mass
import numpy as np
import h5py
import os

def mass_analyze(fname, nfname, hdf5_filename, hdf5_noisefilename, preknowledge_filename):

    data = mass.TESGroup([fname],[nfname], hdf5_filename=hdf5_filename, hdf5_noisefilename=hdf5_noisefilename)
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
        g = h5.require_group("chan%g"%ds.channum)

        # KNOWN PROBLEM: julia fails to read phython written strings

        g.require_group("physical")
        g["physical"]["x_um_from_array_center"]=0
        g["physical"]["y_um_from_array_center"]=0
        g["physical"]["collimator open area"]=0
        g["physical"]["frametime"]=ds.timebase

        g.require_group("trigger")
        g["trigger"]["nsamples"]=ds.nSamples
        g["trigger"]["npresamples"]=ds.nPresamples
        g["trigger"]["avoid_edge"]=True
        g["trigger"]["type"]="edge"
        g["trigger"]["level_specify_units_in_name"]=0.1

        g.require_group("filter")
        g["filter"]["data_file_used"]=ds.filename
        g["filter"]["values"] = ds.filter.filt_noconst
        g["filter"]["values_at"] = ds.filter.filt_aterms.reshape((-1,))
        g["filter"]["f3db"] = 100000000.0 # its none, want a float
        g["filter"]["average_pulse"] = ds.filter.avg_signal
        g["filter"]["average_pulse_energy_eV"]=5989.0
        g["filter"]["description"] = "noconst"
        g["filter"]["shift_threshold"] = int(round(4.3*np.median(ds.p_pretrig_rms[ds.good()])))

        g.require_group("cuts")
        g["cuts"]["pretrigger_rms"] = [0.0,30.0]
        g["cuts"]["postpeak_deriv"] = [0.0,20.0]

        g.require_group("calibration")
        g["calibration"].require_group("p_filt_value")
        g["calibration"]["p_filt_value"]["data_file_used"] = ds.filename
        g["calibration"]["p_filt_value"]["lines_used"] = "MnKAlpha, MnKBeta"
        g["calibration"]["p_filt_value"]["energies"] = [1,2]
        g["calibration"]["p_filt_value"]["ph"] = [1,2]
        g["calibration"]["p_filt_value"]["de"] = [1,2]
        g["calibration"]["p_filt_value"]["dph"] = [1,2]

        g["analysis_type"]="mass compatible feb 2017"

    return data


if __name__ == "__main__":
    fname = os.path.expanduser("~/.julia/v0.5/ReferenceMicrocalFiles/ljh/20150707_D_chan13.ljh")
    nfname = os.path.expanduser("~/.julia/v0.5/ReferenceMicrocalFiles/ljh/20150707_C_chan13.noi")
    hdf5_filename = os.path.expanduser("~/.julia/v0.5/Pope/test/mass.h5")
    hdf5_noisefilename = os.path.expanduser("~/.julia/v0.5/Pope/test/mass_noise.h5")
    preknowledge_filename = os.path.expanduser("~/.julia/v0.5/Pope/test/preknowledge.h5")
    if os.path.isfile(hdf5_filename): os.remove(hdf5_filename)
    if os.path.isfile(preknowledge_filename): os.remove(preknowledge_filename)
    if os.path.isfile(hdf5_noisefilename): os.remove(hdf5_noisefilename)
    data=mass_analyze(fname, nfname, hdf5_filename, hdf5_noisefilename, preknowledge_filename)
