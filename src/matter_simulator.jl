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
  for record in ljh0
    sleep_s = clamp((record.timestamp_usec-tlast)*1e-6,0,timeout_s)
    tlast = record.timestamp_usec
    sleep(sleep_s)
    # write(ljh1, record.rowcount, record.timestamp_usec, record.data)
    write(ljh1,record)
  end
  close(ljh0)
  close(ljh1)
end

function mattersimprogress(srcnames, destnames, tasks)
  srcs_size = sum(stat(src).size for src in srcnames)
  dests_size = sum(stat(dest).size for dest in destnames)
  p = Progress(srcs_size,1)
  while dests_size < srcs_size && !all(istaskdone.(tasks))
    update!(p,dests_size)
    sleep(0.5)
    dests_size = sum(stat(dest).size for dest in destnames)
  end
end

function mattersim(srcdir, destdir, timeout_s=1)
  channels = LJHUtil.allchannels(srcdir)
  srcnames = LJHUtil.fnames(srcdir, channels)
  length(srcnames)>0 || error("found no ljh files in $srcdir")
  destnames = LJHUtil.fnames(destdir, channels)
  isdir(destdir) || mkdir(destdir)
  tasks = [@task timed_ljh_rewriter(src,dest,timeout_s) for (src,dest) in zip(srcnames, destnames)]
  LJHUtil.write_sentinel_file(destnames[1],true)
  @schedule mattersimprogress(srcnames, destnames, tasks)
  schedule.(tasks)
  wait.(tasks)
  LJHUtil.write_sentinel_file(destnames[1],false)
end
