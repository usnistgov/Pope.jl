# python code from mass/src/mass/core/channel.py

# def _filter_data_segment_new(self, filter_values, filter_AT, first, end, transform=None):
#     """single-lag filter developed in 2015"""
#     if first >= self.nPulses:
#         return None, None
#
#     assert len(filter_values) + 1 == self.nSamples
#
#     seg_size = end - first
#     assert seg_size == self.data.shape[0]
#     ptmean = self.p_pretrig_mean[first:end]
#     data = self.data
#     if transform is not None:
#         ptmean.shape = (seg_size, 1)
#         data = transform(self.data - ptmean)
#         ptmean.shape = (seg_size,)
#     conv0 = np.dot(data[:, 1:], filter_values)
#     conv1 = np.dot(data[:, 1:], filter_AT)
#
#     # Find pulses that triggered 1 sample too late and "want to shift"
#     want_to_shift = self.p_shift1[first:end]
#     conv0[want_to_shift] = np.dot(data[want_to_shift, :-1], filter_values)
#     conv1[want_to_shift] = np.dot(data[want_to_shift, :-1], filter_AT)
#     AT = conv1 / conv0
#     return AT, conv0

"""
filter_single_lag(data, filter, filter_at, pretrig_mean, npresamples, shift_threshold)
Filter a sinlge pulse record `data` with Joe Fowler's single lag technique,
translated from mass/src/mass/core/channel.py `_filter_data_segment_new`.
`data` is convolved with both `filter` and `filter_at`. `filter_at` is intended to be the
derivative of `filter` and is used for creating an arrival time indicator.
if the difference between the last two pre-rise points exceeds `shift_threshold`,
the data is shifted by one lag before convolution
"""
function filter_single_lag(data, filter, filter_at, pretrig_mean, npresamples, shift_threshold)
  length(data) == length(filter)+1 || error("filter and data don't match")
  needshift = (data[npresamples+3]-pretrig_mean > shift_threshold)
  if needshift
    conv0 = dot(@view(data[2:end]), filter)
    conv1 = dot(@view(data[2:end]), filter_at)
  else
    conv0 = dot(@view(data[1:end-1]), filter)
    conv1 = dot(@view(data[1:end-1]), filter_at)
  end
  arrival_time_indicator = conv1/conv0
  arrival_time_indicator,conv0
end
