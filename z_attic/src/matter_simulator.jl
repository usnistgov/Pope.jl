using ProgressMeter

"    timed_ljh_rewriter(src, dest, timeout_s, pulses_written, pulses_total, i)
Open the ljh file at path `src`. Copy it's header to a file at `dest`, overwiting any existing file with that name.
Then write records from `src` to `dest`, pausing between each write by the difference between successive timestamps.
The maximum pause time (in seconds) for a single record is given by `timeout_s`. After completion the files `src` and `dest`
will be identical. `pulses_written` is an array, this process will increment `pulses_written[i]` each time it writes a pulse.
`pulses_total` is an array, this process will write the number of pulses in src to `pulses_total[i]` "
function timed_ljh_rewriter(src, dest, timeout_s, fastforward, pulses_written, pulses_total, i)
  ljh0 = LJH.LJHFile(src)
  #write hearder to dest file
  f = open(dest,"w+")
  seekstart(ljh0.io)
  write(f, read(ljh0.io,ljh0.datastartpos))
  flush(f)
  seekstart(f)
  ljh1 = LJH.LJHFile(dest, f)
  pulses_total[i] = length(ljh0)

  if length(ljh0)==0
    return
  end
  record = ljh0[1]
  tlast = record.timestamp_usec
  t_start = time()
  tnext = t_start
  for record in ljh0
    tnext += clamp((record.timestamp_usec-tlast)*1e-6/fastforward,0,timeout_s)
    tlast = record.timestamp_usec
    to_sleep_s = max(0.0,tnext-time())
    if to_sleep_s>=0.001 #minimum sleep time is 0.001 s, don't bother sleeping
      sleep(to_sleep_s)
    end
    write(ljh1,record)
    pulses_written[i]+=1
  end
  close(ljh0)
  close(ljh1)
  return
end

function mattersimprogress(srcnames, destnames, tasks, channels, timeout_s, pulses_written, pulses_total)
  println("\nMatter Simulator Running on $(length(channels)) channels, with timeout = $timeout_s s")
  println("Channel numbers: $channels")
  println("First input file: $(first(srcnames))")
  println("First output file: $(first(destnames))")
  println("Process pid = $(getpid())")
  flush(STDOUT)
  # srcs_size = sum(stat(src).size for src in srcnames)
  # dests_size = sum(stat(dest).size for dest in destnames)
  ntotal = sum(pulses_total)
  nwritten = sum(pulses_written)
  p = Progress(ntotal,0.5,"Matter Simulator: ")
  i=0
  while nwritten < ntotal && !all(istaskdone.(tasks))
    ProgressMeter.update!(p,nwritten)
    sleep(0.5)
    i+=1
    if i==10
      i=0
      println("\n$nwritten pulses written in $(p.tlast-p.tfirst) seconds, $(nwritten/(p.tlast-p.tfirst)) cps avg")
    end
    nwritten = sum(pulses_written)
    # dests_size = sum(stat(dest).size for dest in destnames)
  end
  ProgressMeter.update!(p, nwritten) # make sure it reads 100% finished if it  is
  if nwritten == ntotal
    println("\nMatter Simulator finished.")
  else
    println("\nMatter Simulator finished without writing all data.")
  end
  println("Time elapsed: $(p.tlast-p.tfirst) seconds.")
  dests_size = sum(stat(dest).size for dest in destnames)
  println("Total bytes written $dests_size.")
end

"    mattersim(srcdir, destdir, timeout_s=0.01, maxchannels=240)"
function mattersim(srcdir, destdir, timeout_s=0.01, fastforward=1.0, maxchannels=240)
  maxchannels<=0 && error("maxchannels must be positive, was $maxchannels")
  ljhdict = LJH.allchannels(srcdir, maxchannels) # ordered dict mapping channel number to filename
  length(ljhdict)>0 || error("found no ljh files in $srcdir")
  isdir(destdir) || mkdir(destdir)
  destnames = LJH.fnames(destdir, keys(ljhdict))
  pulses_written = zeros(Int, length(ljhdict)) # used to record how many pulses have been written
  pulses_total = zeros(Int, length(ljhdict))
  # i is an index for writinginto pulses_written and pulses_total
  tasks = [@task timed_ljh_rewriter(src, dest, timeout_s, fastforward, pulses_written, pulses_total, i) for (i,(src,dest)) in enumerate(zip(values(ljhdict), destnames))]
  LJH.write_sentinel_file(destnames[1],true)
  println("Matter simulator wrote sentinel file: $(destnames[1]), true")
  progresstask = @async mattersimprogress(values(ljhdict), destnames, tasks, keys(ljhdict), timeout_s, pulses_written, pulses_total)
  schedule.(tasks)
  wait.(tasks)
  wait(progresstask)
  LJH.write_sentinel_file(destnames[1],false)
  println("Matter simulator wrote sentinel file: $(destnames[1]), false")
end
