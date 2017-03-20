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
  min_val = typemax(Int)
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

  postpeak_deriv = max_timeseries_deriv_mass(data, average_pulse_peak_index)
  # @show length(data)
  # @show average_pulse_peak_index, npresamples, nsamples
  # @show deriv_range = average_pulse_peak_index:length(data)
  # deriv_work = zeros(length(deriv_range))
  # deriv_data = data[deriv_range]
  # @show typeof(deriv_data), typeof(deriv_work)
  # postpeak_deriv = max_timeseries_deriv!(deriv_work, deriv_data, true)

  if 0<=peak_val-ptm<=typemax(UInt16)
    peak_val_ret = round(Int,peak_val-ptm)
  else
    peak_val_ret=0
  end

  # Copy results into the PulseSummaries object
  pulse_average = s/npostsamples-ptm
  pulse_rms = sqrt(abs(s2/npostsamples - ptm*(ptm+2*pulse_average)))
  PulseSummary(ptm, pretrig_rms, pulse_average, pulse_rms, rise_time,
   postpeak_deriv, peak_idx, peak_val_ret, min_val)
end

"estimate_rise_time(pulserecord, searchrange, peakval, ptm, frametime)
uses the slope between the 10 and 90 percent points to extrapolate rise time to 100 percent
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
    for j = idx10:peakindex
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
    #divide out fraction rise to extrapolate to 10% rise time
    fracrise = (pulserecord[idx90]-pulserecord[idx10])/(peakval-ptm)
    rise_time = (idx90-idx10)*frametime/fracrise
    return rise_time
end

function max_timeseries_deriv_mass(p, s)
  #following mass.analysis_algorithms.compute_max_deriv
  # use filter=SG and spike reject = true options from mass, not optional
  N = length(p)
  Nk = 5
  k1,k2,k3,k4,k5=2,1,0,-1,-2 # default kernel from mass
  t_max_deriv=0

  t0 = k5 * p[s+1] + k4 * p[s+2] + k3 * p[s+3] + k2 * p[s+4] + k1 * p[s+5]
  t1 = k5 * p[s+2] + k4 * p[s+3] + k3 * p[s+4] + k2 * p[s+5] + k1 * p[s+6]
  t2 = k5 * p[s+3] + k4 * p[s+4] + k3 * p[s+5] + k2 * p[s+6] + k1 * p[s+7]
  t_max_deriv = min(t2,t0)

  for j=s+8:N
    t3 = k5 * p[j-4] + k4*p[j-3] + k3*p[j-2] + k2*p[j-1] + k1*p[j]
          # t4 = t3 if t3 < t1 else t1
    t4 = t3<t1 ? t3 : t1
    t_max_deriv = max(t4,t_max_deriv)
    t0, t1, t2 = t1, t2, t3
  end
  t_max_deriv/10
end
