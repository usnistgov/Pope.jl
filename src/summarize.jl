immutable PulseSummary
  pretrig_mean      ::Float64
  pretrig_rms       ::Float64
  pulse_average     ::Float64
  pulse_rms         ::Float64
  rise_time         ::Float64
  postpeak_deriv    ::Float64
  peak_index        ::Int16
  peak_value        ::UInt16
  min_value         ::UInt16
end

function summary(data::LJH.LJHRecord, npresamples, nsamples, average_pulse_peak_index, frametime)
  summarize(data.data, npresamples, nsamples, average_pulse_peak_index, frametime)
end

function summarize(data::Vector, npresamples, nsamples, average_pulse_peak_index, frametime)
  length(data) == nsamples || error("wrong length data. nsamples: $nsamples\n data: $data")
  s = s2 = 0
  min_idx = 0
  peak_idx = 0
  peak_val = 0
  min_idx = 0
  min_val = 0
  npostsamples = length(data)-npresamples
  for j = 1:npresamples
      d=Int(data[j])
      if d > peak_val
          peak_idx, peak_val = j, d
      elseif d < min_val
          min_idx, min_val = j,d
      end
      s+=d
      s2+=d*d
  end
  ptm = s/npresamples # pre trigger mean
  pretrig_rms = sqrt(abs(s2/npresamples - ptm*ptm))

  # Now post-trigger calculations
  s = s2 = 0
  for j = npresamples+1:length(data)
      d=Int(data[j])
      if d > peak_val
          peak_idx, peak_val = j, d
      elseif d < min_val
          min_idx, min_val = j,d
      end
      # d2=d-ptm
      s+=d
      s2+=d*d
  end

  rise_time::Float64 = estimate_rise_time(data, npresamples+1:peak_idx,
                                 peak_val, ptm, frametime)

  postpeak_deriv = max_timeseries_deriv_simple(data, average_pulse_peak_index)

  # Copy results into the PulseSummaries object
  pulse_average = s/npostsamples-ptm
  pulse_rms = sqrt(abs(s2/npostsamples - ptm*(ptm+2*pulse_average)))
  if ptm < 0
      _peak_val = round(UInt16,peak_val)
  elseif peak_val > ptm
      _peak_val = round(UInt16,peak_val - ptm)
  else # peak_val < ptm
      _peak_val = UInt16(0)
  end
  PulseSummary(ptm, pretrig_rms, pulse_average, pulse_rms, rise_time,
   postpeak_deriv, peak_idx, peak_val, min_val)
end

"estimate_rise_time(pulserecord, searchrange, peakval, ptm, frametime)
`pulserecord` = Vector
`searchrange` = range to look for risetime in, should go from base of pulse to peak, last(searchrange) is peakindex
`peakval` = maximum(pulserecord[postrig_region], has not had ptm subtracted off)
`ptm` = pretrigger mean
`frametime` = time spacing between points"
function estimate_rise_time(pulserecord, searchrange, peakval,ptm,frametime)
    idx10 = first(searchrange)
    peakindex = last(searchrange)
    (peakindex > length(pulserecord) || length(searchrange)==0) && (return Float64(length(pulserecord)))

    idx90 = peakindex
    thresh10 = 0.1*(peakval-ptm)+ptm
    thresh90 = 0.9*(peakval-ptm)+ptm
    j=0 # to make j exist after the for loop
    for j = 1:peakindex
        if pulserecord[j] > thresh10
            idx10 = j-1
            break
        end
    end
    for j = j+1:peakindex
        if pulserecord[j] > thresh90
            idx90 = j-1
            break
        end
    end
    rise_time = (idx90-idx10)*frametime
    rise_time
end

"""max_timeseries_deriv_simple(pulserecord, peak_idx)
Returns the maximum difference between succesive points in `pulserecord` after `pulserecord[peak_idx]`
"""
function max_timeseries_deriv_simple(pulserecord, peak_idx)
    max_deriv = typemin(eltype(pulserecord))
    for j = peak_idx:length(pulserecord)-1
        deriv = pulserecord[j+1]-pulserecord[j]
        deriv > max_deriv && (max_deriv = deriv)
    end
    max_deriv
end
