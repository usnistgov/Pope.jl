import matplotlib
import mass
import pylab as plt
import numpy as np
import h5py

filename = "/home/pcuser/.julia/v0.6/Pope/scripts/make_preknowledge_temp.hdf5"
pkfilename = "/home/pcuser/.julia/v0.6/Pope/scripts/pk_1x10_512samples.preknowledge"

data = mass.TESGroupHDF5(filename)
data.set_chan_good(data.why_chan_bad.keys())
mass.TESGroupHDF5.updater = mass.InlineUpdater

plt.ion()
ds=data.channel[3]
data.calibrate("p_filt_value",["PdLGamma1","PdLBeta1","AuL3M5","AuL2M4","AuL3N5"],
	diagnose=False,forceNew=True)
data.convert_to_energy("p_filt_value")
bin_edges = np.arange(0,20000,5)
bin_centers = bin_edges[1:]

counts,_ = np.histogram(ds.p_energy[:],bin_edges)

plt.figure()
plt.plot(bin_centers, counts)

with h5py.File(pkfilename,"r") as h5:
	for grpname in h5.keys():
		grp1=h5[grpname]
		grp2=data.hdf5_file[grpname]
		if not "calculated_cuts/pretrigger_rms" in grp2:
			grp2["calculated_cuts/pretrigger_rms"]=grp1["cuts/pretrigger_rms"].value
			grp2["calculated_cuts/postpeak_deriv"]=grp1["cuts/postpeak_deriv"].value	