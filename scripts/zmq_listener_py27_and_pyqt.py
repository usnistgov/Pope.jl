# This is a sketch of how a popepipe_zmq<->spec interface
# would work
# it is not functional

import zmq
import numpy as np
import time
import mass
PORT = 2015

try:
    import PyQt5
    use_pyqt5=True
except:
    use_pyqt5=False

if use_pyqt5:
    print("using PyQt5")
    from PyQt5 import QtGui ,QtCore, uic
    from PyQt5.QtCore import pyqtSlot
    from PyQt5.QtWidgets import (QApplication, QWidget, QFileDialog, QSizePolicy, QVBoxLayout, QTextEdit,QCheckBox)
    from PyQt5.QtGui import QFont
    from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
    from matplotlib.backends.backend_qt5agg import NavigationToolbar2QT as NavigationToolbar
else:
    print("failed to import PyQt5, trying PyQt4")
    from PyQt4 import QtGui ,QtCore, uic
    from PyQt4.QtCore import pyqtSlot, QTimer
    from PyQt4.QtGui import (QApplication, QWidget, QFileDialog, QSizePolicy, QVBoxLayout, QTextEdit,QCheckBox)
    from PyQt4.QtGui import QFont
    from matplotlib.backends.backend_qt4agg import FigureCanvasQTAgg as FigureCanvas
    from matplotlib.backends.backend_qt4agg import NavigationToolbar2QT as NavigationToolbar


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


class MplCanvas(QWidget):
    def __init__(self, parent = None, width=6, height=5, dpi=100):
        QWidget.__init__(self, parent)
        self.fig = Figure(figsize=(width,height), dpi=dpi)
        # self.fig = Figure()
        self.canvas = FigureCanvas(self.fig)
        FigureCanvas.__init__(self.canvas, self.fig)
        self.axes = self.fig.add_subplot(111)
        self.setSizePolicy(QSizePolicy.MinimumExpanding, QSizePolicy.MinimumExpanding)
        self.canvas.setSizePolicy(QSizePolicy.MinimumExpanding, QSizePolicy.MinimumExpanding)
        self.canvas.updateGeometry()
        self.mpl_toolbar = NavigationToolbar(self.canvas, self)
        self.vbl = QVBoxLayout()
        self.vbl.addWidget(self.mpl_toolbar)
        self.vbl.addWidget(self.canvas)
        self.setLayout(self.vbl)


    def clear(self): self.axes.clear()
    def plot(self, *args, **kwargs): return self.axes.plot(*args, **kwargs)
    def set_xlabel(self, *args, **kwargs): return self.axes.set_xlabel(*args, **kwargs)
    def set_ylabel(self, *args, **kwargs): return self.axes.set_ylabel(*args, **kwargs)
    def set_title(self, *args, **kwargs): return self.axes.set_title(*args, **kwargs)
    def set_yscale(self,*args, **kwargs): return self.axes.set_yscale(*args, **kwargs)
    def legend(self, *args, **kwargs): return self.axes.legend(*args, **kwargs)
    def mpl_connect(self, *args, **kwargs): return self.canvas.mpl_connect(*args, **kwargs)
    def draw(self, *args, **kwargs): return self.canvas.draw(*args, **kwargs)
    def onpick(self, event):
        print("default pick_event handler for MplCanvas")
        print(event.artist)
        print(event.ind)


ctx = zmq.Context() # context is required to create zmq socket
socket = zmq.Socket(ctx, zmq.SUB) # make a subscriber socket
socket.connect ("tcp://localhost:%s" % PORT) # connect to the server
socket.set_hwm(10000) # set the recieve side message buffer limit
socket.setsockopt(zmq.SUBSCRIBE, "") # subscribe to all message, since all start with ""
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
    return (not pt_lo<payload["pretrig_rms"]<pt_hi) or (not md_lo<payload["postpeak_deriv"]<md_hi)
    # return False

def get_counts(info):
    energies = []
    i=-1
    while True:
        i+=1
        # read all available message, return when none are availble
        try:
            m = socket.recv_multipart(flags=zmq.NOBLOCK)
            if m[0].startswith("header"): continue
            ch = int(m[0])
            payload = np.fromstring(m[1],dtype_MassCompatibleDataProductFeb2017,1)[0]
            if ch in info.keys() and not iscut(payload,ch,info):
                energies.append(apply_calibration(payload,ch,info))
            else:
                pass
                # print ch
                # print apply_calibration(payload,ch,info)
        except zmq.ZMQError:
            break
    print("%d/%d payloads used"%(len(energies),i))
    return energies

class MyCanvas(MplCanvas):
    def __init__(self):
        print("mpl init")
        MplCanvas.__init__(self)
        print("calfile")
        calfile = h5py.File(args["calibrationpath"],"r")
        info = {}
        for (k,v) in calfile.iteritems():
            chnum = int(k[4:])
            grp = calfile[k]
            if chnum%2==0: continue
            pt=grp["calculated_cuts"]["pretrigger_rms"].value
            md=grp["calculated_cuts"]["postpeak_deriv"].value
            cal=mass.EnergyCalibration.load_from_hdf5(grp["calibration"],"p_filt_value")
            info[chnum] = (pt,md,cal)
        print("mid init")
        self.info = info
        self.bin_edges = np.arange(2500,13000,2.0)
        self.bin_centers = 0.5*(self.bin_edges[1:]+self.bin_edges[:-1])
        self.counts = np.zeros_like(self.bin_centers,dtype="int")
        print("making timer")
        self.timer = QTimer()
        self.timer.timeout.connect(self.tick)
        self.timer.start(500)
        print("done init")
        self.checkbox = QCheckBox(self)

    def tick(self):
        print("tick!!")
        energies = get_counts(self.info)
        energies = [energy for energy in energies if not np.isnan(energy)]
        newcounts,_ = np.histogram(energies, self.bin_edges)
        self.counts+=newcounts
        if self.checkbox.isChecked():
            self.line2d.set_ydata(self.counts)
        else:
            self.clear()
            self.line2d = self.plot(self.bin_centers, self.counts)[0]
            self.set_xlabel("energy (eV)")
            self.set_ylabel("counts per 1 eV bin")
            # self.set_yscale("log")
        self.set_title("%d counts"%(self.counts.sum()))
        self.draw()


if __name__=="__main__":
    import h5py
    import pylab as plt
    import numpy as np

    app = QApplication(sys.argv)
    w = MyCanvas()
    w.setWindowTitle('Popeviewer')
    w.show()


    sys.exit(app.exec_())
