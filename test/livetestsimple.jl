if nprocs() == 1
  addprocs(1)
  println("added 1 proc")
end
using Pope: LJH, LJHUtil
using HDF5


data = collect(UInt16(0):UInt16(999))
nsamples = length(data)
filter = zeros(nsamples-1)
filter_at = zeros(nsamples-1)
npresamples = 200
average_pulse_peak_index = 250
shift_threshold = 5
channels = 1:2:480
frametime = 9.6e-6
dname,endchannel,ljhmadechannel,s=LJH.launch_writer_other_process(dt=frametime,channels=channels,npre=npresamples,data=data)

h5 = h5open(tempname(),"w")

wait(ljhmadechannel)

readers = []
fname=""
for channel in channels
  fname = LJHUtil.fnames(dname, channel)
  analyzer = Pope.MassCompatibleAnalysisFeb2017(filter, filter_at, npresamples, nsamples, average_pulse_peak_index, frametime, shift_threshold)
  product_writer = Pope.make_buffered_hdf5_writer(h5, channel)
  reader = Pope.launch_reader(fname, analyzer, product_writer;continuous=true)
  push!(readers, reader)
end

wait(@schedule begin sleep(5);put!(endchannel,true); println("other process writing STOPPED") end)
wait(@schedule  begin sleep(1);map(r->close(r.product_writer), readers) end)
#ljh = LJH.LJHFile(LJHUtil.fnames(dname, 1))
# @show ljh[end]
# @show divrem(ljh)
