if nprocs() == 1
  addprocs(1)
  println("added 1 proc")
end
using Pope: LJH, LJHUtil
using HDF5


data = collect(UInt16(0):UInt16(999))
nsamples = length(data)
filter_values = zeros(nsamples-1)
filter_at = zeros(nsamples-1)
npresamples = 200
average_pulse_peak_index = 250
shift_threshold = 5
channels = 1:2:480
frametime = 9.6e-6
dname,endchannel,ljhmadechannel,s=LJH.launch_writer_other_process(dt=frametime,channels=channels,npre=npresamples,data=data)
wait(ljhmadechannel) # this

h5 = h5open(tempname(),"w")

readers = []
fname=""
for channel in channels
  fname = LJHUtil.fnames(dname, channel)
  analyzer = Pope.MassCompatibleAnalysisFeb2017(filter_values, filter_at, npresamples, nsamples, average_pulse_peak_index, frametime, shift_threshold)
  product_writer = Pope.make_buffered_hdf5_writer(h5, channel)
  reader = Pope.launch_reader(fname, analyzer, product_writer;continuous=true)
  push!(readers, reader)
end

runtime = 30
wait(@schedule begin sleep(runtime);put!(endchannel,true); println("other process writing STOPPED") end);
sleep(3) # make sure ljh files are all fully written, I do get errors without this
Pope.stop.(readers)
wait.(readers)


function check_values(channel, h5)
  fname = LJHUtil.fnames(dname, channel)
  ljh = LJH.LJHFile(fname)
  @show channel, length(ljh)
  @assert 80<length(ljh)/runtime<120  # the efault value in launch_writer_other_process has 100 cps
  g = h5["chan$channel"]
  for name in names(g)
    @assert length(g[name])==length(ljh)
  end
  @assert(read(g["rowcount"])==collect(1:length(ljh)))
end

for channel in channels
  check_values(channel,h5)
end
