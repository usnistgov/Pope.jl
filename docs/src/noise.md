# Module NoiseAnalysis

Module `Pope.NoiseAnalysis` contains tools for the analysis of noise data. This
includes computation of:
* noise autocorrelation function,
* power-spectral density, and
* a low-order ARMA model that represents the autocorrelation.

The results of these calculations are contained in the struct `NoiseResult`, which can
be stored in and loaded from a standard HDF5 format, through the functions 
`hdf5save()` and `hdf5load()`.

Power spectra require a window function. We suggest `NoiseAnalysis.bartlett` as
a default. Package `DSP.jl` has many others in its module `DSP.Windows`, but it does
not seem important enough to be worth adding it as a full dependency here.

## Automatic Analysis Script 
The script `scripts/noise_analysis.jl` analyzes one or more LJH-format 
files that contain noise data. Basic usage is like this:

```bash
path_to/scripts/noise_analysis.jl -r /Data/path/20171225_christmasdata_chan*.noi
```

This will operate on all noise files that match the filename expansion. You may
enter multiple filenames and/or expansion patterns in one call. For each
file, the appropriate output filename will be inferred by replacing the suffix
`_chanNNN.ljh` or `_chanNNN.noi` with `_noise.hdf5`. Optional command-line arguments:

* `-r`: Any existing HDF5 file will be deleted before proceeding to write to it. Without this, it's an error to (try to) write to an HDF5 file that already exists.
* `-u`: Any existing HDF5 file may be updated by adding new channels to it (but it remains an error to write to a file if it already contains the channel).
* `-o ofile.hdf5`: write all output to the specified file instead of the inferred filename.
* `-n 500`: Compute the autocorrelation to this many lags, counting the 0-lag value (the variance) as the first. If not given, the number of lags will match the record length in the input file.
* `-f 1025`: Compute the power-spectral density at this many discrete frequencies (if not given, will match `1+L//2` for records of length `L`). Because the autocorrelation and the power spectrum are computed separately, the length of the two results can be specified independently.
