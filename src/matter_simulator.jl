using ProgressMeter

"timed_ljh_rewriter(src, dest, timeout_s)
Open the ljh file at path `src`. Copy it's header to a file at `dest`, overwiting any existing file with that name.
Then write records from `src` to `dest`, pausing between each write by the difference between successive timestamps.
The maximum pause time (in seconds) for a single record is given by `timeout_s`. After completion the files `src` and `dest`
will be identical."
function timed_ljh_rewriter(src, dest, timeout_s)
  ljh0 = LJH.LJHFile(src)
  #write hearder to dest file
  f = open(dest,"w+")
  seekstart(ljh0.io)
  write(f, read(ljh0.io,ljh0.datastartpos))
  flush(f)
  seekstart(f)
  ljh1 = LJH.LJHFile(dest, f)

  if length(ljh0)==0
    return
  end
  record = ljh0[1]
  tlast = record.timestamp_usec
  defered_sleep_s = 0.0
  for record in ljh0
    sleep_s = clamp((record.timestamp_usec-tlast)*1e-6,0,timeout_s)
    tlast = record.timestamp_usec
    if sleep_s>0.001 #minimum sleep time is 0.001 s, make a fast path for short sleeps
      sleep(sleep_s)
    else
      defered_sleep_s+=sleep_s
      if defered_sleep_s>=0.001
        sleep(defered_sleep_s)
        defered_sleep_s=0.0
      end
    end
    write(ljh1,record)
  end
  close(ljh0)
  close(ljh1)
end

function mattersimprogress(srcnames, destnames, tasks, channels, timeout_s)
  println("\nMatter Simulator Running on $(length(srcnames)) channels, with timeout = $timeout_s s")
  println("Channel numbers: $channels")
  println("First input file: $(srcnames[1])")
  println("First output file: $(destnames[1])")
  println("Process pid = $(getpid())")
  flush(STDOUT)
  srcs_size = sum(stat(src).size for src in srcnames)
  dests_size = sum(stat(dest).size for dest in destnames)
  p = Progress(srcs_size,0.5,"Matter Simulator: ")
  while dests_size < srcs_size && !all(istaskdone.(tasks))
    update!(p,dests_size)
    sleep(0.1)
    dests_size = sum(stat(dest).size for dest in destnames)
  end
  if dests_size == srcs_size
    update!(p, srcs_size) # make sure it reads 100% finished if it  is
    println("\nMatter Simulator finished.")
  else
    println("\nMatter Simulator finished without writing all data.")
  end
  println("Time elapsed: $(p.tlast-p.tfirst) seconds.")
  println("Total bytes written $dests_size.")
end

"mattersim(srcdir, destdir, timeout_s=0.01, maxchannels=240)"
function mattersim(srcdir, destdir, timeout_s=0.01, maxchannels=240)
  maxchannels<=0 && error("maxchannels must be positive, was $maxchannels")
  channels = LJHUtil.allchannels(srcdir)
  channels = channels[1:min(maxchannels, length(channels))]
  srcnames = LJHUtil.fnames(srcdir, channels)
  length(srcnames)>0 || error("found no ljh files in $srcdir")
  isdir(destdir) || mkdir(destdir)
  destnames = LJHUtil.fnames(destdir, channels)
  tasks = [@task timed_ljh_rewriter(src,dest,timeout_s) for (src,dest) in zip(srcnames, destnames)]
  LJHUtil.write_sentinel_file(destnames[1],true)
  println("Matter simulator wrote sentinel file: $(destnames[1]), true")
  progresstask = @schedule mattersimprogress(srcnames, destnames, tasks, channels, timeout_s)
  schedule.(tasks)
  wait.(tasks)
  wait(progresstask)
  LJHUtil.write_sentinel_file(destnames[1],false)
  println("Matter simulator wrote sentinel file: $(destnames[1]), false")
end
