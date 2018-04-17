## Go to right directory
* Both Terminals
cd ~/.julia/v0.6/Pope/scripts

## Make Preknowledge
* Terminal 1
* Adjust Filenames
  * First filename is pulse file
  * Second filename is noise file
./make_preknowledge.py /home/pcuser/data/MM2018C/20180412/20180412_A/20180412_111330_chan11.ljh /home/pcuser/data/MM2018C/20180412/20180412_B/20180412_114302_chan1.ljh  --quality_report --overwriteoutput --apply_filter

## Build the calibration, no need to adjust filenames unless you change from 1x10:
* Terminal 1
* If multiplexing factor has changed from 1x10, adjust filenames
python make_calibration.py

## Launch Pope
* Terminal 1
./popewatchesmatter.jl --overwriteoutput pk_1x4_1024samples.preknowledge

## Launch Viewer
* Terminal 1
python zmq_listener_py27_and_pyqt.py make_preknowledge_temp.hdf5

## In Matter, start writing pulses to disk
* Pope should detect all file writing starts, and start analyzing.
* The viewer should happily add data from one ljh file to the plots made with another ljh file.

## How to Use Viewer
* If you want to zoom the plot, click the box in the top left to stop it from auto-zooming out. * * Close viewer with the X in top left.
* Restart the viewer to clear the spectrum.


## To Close Pope
* Terminal 2
./endpopewatchesmatter.jl
