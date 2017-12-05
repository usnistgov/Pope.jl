# Scripts

Most of Pope.jl's functionality is intended to be used via scripts. They are found
in `Pope/scripts`. All the scripts have help pages available with the `-h` argument.

For example
```
687gombp:~ $ cd .julia/v0.6/Pope/scripts
687gombp:scripts oneilg$ ./popeonce.jl -h
Pope (Pass one pulse examiner)
Usage:
  popeonce.jl <ljhpath> <preknowledge> <output>
  popeonce.jl --overwriteoutput <ljhpath> <preknowledge> <output>
  popeonce.jl -h | --help
...
```

## Mass Compatible Workflow

This is the workflow used at the SSRL roughly. I'm leaving out all the optional arguments, and maybe event some required arguments.

1. `make_preknowledge.py pulse_file noise_file`
  * Creates a preknowledge file for further use.
2. `popewatchermatter.jl preknowledge_file`
  * Starts a process that watches matter (via the sentinel file in ~/.daq) and automatically starts processing any files that begin writing after this is started.
3. `endpopewatchesmatter.jl`
  * Gracefully stop process of `popewatchesmatter.jl`.

## Utilities

  * `popeonce.jl pulse_file preknowledge_file` Will apply the basis in `preknowledge_file` to each pulse of each file in `pulse_file`.
  * `checker.jl dir` Checks to make sure each subdirectory containing ljh files has pope output, and can create a script that will run `popeonce` on each of those directories.

## Testing

  * `benchmark.jl` Sets up two processes, one writing LJH files, another analyzing them. Lets you check CPU usage.
  * `matter_simulator.jl pulse_file` Reads LJH files, and writes them to new LJH files. Has options for controlling the timing of writing, to match original timing, or to go faster.

## ZMQ Listeners
There are a variety of files with names like `zmq_listener*`. These files demonstrate how to listen to the ZMQ output of Pope, and some may include plotting results.
