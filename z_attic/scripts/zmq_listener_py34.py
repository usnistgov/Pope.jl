# This is a sketch of how a popepipe_zmq<->spec interface
# would work
# it is not functional

import zmq
import numpy as np
import time
import mass
PORT = 2015

import os, sys, h5py
import numpy as np
import pylab as plt
from matplotlib.figure import Figure
from mass.core.files import LJHFile
import mass
import argparse

parser = argparse.ArgumentParser(description='A work in progress program to display a live spectrum.',
    epilog="""WARNING, PROBABLY NEEDS WORK ON CUTS""")
parser.add_argument('calibrationpath', help='path of a mass hdf5 file containing calibration info')
args = vars(parser.parse_args())


ctx = zmq.Context() # context is required to create zmq socket
socket = zmq.Socket(ctx, zmq.SUB) # make a subscriber socket
socket.connect ("tcp://localhost:%s" % PORT) # connect to the server
socket.set_hwm(10000) # set the recieve side message buffer limit
socket.setsockopt_string(zmq.SUBSCRIBE, "") # subscribe to all message, since all start with ""
# define a dtype to match the julia type
dtype_MassCompatibleDataProductFeb2017=np.dtype([("filt_value","f4"),("filt_phase","f4"),("timestamp","f8"),("rowcount",
"i8"),("pretrig_mean","f4"),("pretrig_rms","f4"),("pulse_average","f4"),("pulse_rms","f4"),
("rise_time","f4"),("postpeak_deriv","f4"),("peak_index","u2"),("peak_value","u2"),("min_value","u2")])


class CalFile():
    def __init__(self, filename):
        self.h5 = h5py.File(filename,"r")
        print(self.h5)

    def get_hdf5_group(self,ch):
        return self.h5["chan"+str(ch)]["calibration"]

    def get_calibration(self,ch):
        hdf5_group = self.get_hdf5_group(ch)
        return mass.EnergyCalibration.load_from_hdf5(hdf5_group,"p_filt_value")

    def isbad(self,ch):
        return "why_bad" in self.h5["chan"+str(ch)].attrs


def apply_calibration(payload, ch, info):
    cal=info[ch][2]
    return cal(payload["filt_value"])

def iscut(payload, ch, info):
    info_ch = info[ch]
    pt_lo,pt_hi = info_ch[0]
    md_lo,md_hi = info_ch[1]
    v=payload["filt_value"]
    return pt_lo<v<pt_hi and md_lo<v<md_hi

def get_counts(info):
    energies = []
    i=0
    while True:
        i+=1
        # read all available message, return when none are availble
        try:
            m = socket.recv_multipart(flags=zmq.NOBLOCK)
            if m[0].startswith(b"header"): continue
            ch = int(m[0])
            payload = np.fromstring(m[1],dtype_MassCompatibleDataProductFeb2017,1)[0]
            if ch in info.keys() and not iscut(payload,ch,info):
                energies.append(apply_calibration(payload,ch,info))
        except zmq.ZMQError:
            break
    print("%d/%d payloads used"%(len(energies),i))
    return energies



calfile = h5py.File("20170913/20170913_B/20170913_B_mass.hdf5","r")
info = {}
for (k,v) in calfile.items():
    chnum = int(k[4:])
    grp = calfile[k]
    if "why_bad" in grp.attrs.keys():
        continue
    # pt=grp["calculated_cuts"]["pretrig_rms"].value
    # md=grp["calculated_cuts"]["postpeak_deriv"].value
    # pt = [0,20]
    # md = [0,20]

    cal=mass.EnergyCalibration.load_from_hdf5(grp["calibration"],"p_filt_value_phc")
    info[chnum] = (pt,md,cal)
print("mid init")
bin_edges = np.arange(4000,10000,1.0)
bin_centers = 0.5*(bin_edges[1:]+bin_edges[:-1])
counts = np.zeros_like(bin_centers,dtype="int")
plt.ion()


plt.figure()
plt.xlabel("energy (eV)")
plt.ylabel("counts per 1 eV bin")
line2d = plt.plot(bin_centers, counts)[0]
plt.title("%d counts"%(counts.sum()))

def tick():
    print("tick!!")
    energies = np.array(get_counts(info))
    newcounts,_ = np.histogram(energies[~np.isnan(energies)], bin_edges)
    global counts
    counts+=newcounts
    global line2d
    line2d.set_ydata(counts)
    ilo,ihi = np.searchsorted(bin_centers, plt.xlim())
    plt.ylim(0,np.max(counts[ilo:ihi])*1.05)
    plt.draw()
    plt.show()

while True:
    tick()
    plt.pause(1)
