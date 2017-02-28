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

  postpeak_deriv = max_timeseries_deriv_simple(data, average_pulse_peak_index)
  # @show length(data)
  # @show average_pulse_peak_index, npresamples, nsamples
  # @show deriv_range = average_pulse_peak_index:length(data)
  # deriv_work = zeros(length(deriv_range))
  # deriv_data = data[deriv_range]
  # @show typeof(deriv_data), typeof(deriv_work)
  # postpeak_deriv = max_timeseries_deriv!(deriv_work, deriv_data, true)

  # Copy results into the PulseSummaries object
  pulse_average = s/npostsamples-ptm
  pulse_rms = sqrt(abs(s2/npostsamples - ptm*(ptm+2*pulse_average)))
  PulseSummary(ptm, pretrig_rms, pulse_average, pulse_rms, rise_time,
   postpeak_deriv, peak_idx, peak_val, min_val)
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
    #divide out fraction rise to extrapolate to 10% rise time
    fracrise = (pulserecord[idx90]-pulserecord[idx10])/(peakval-ptm)
    rise_time = (idx90-idx10)*frametime/fracrise
    rise_time
end


"""max_timeseries_deriv_simple(pulserecord, peak_idx)
Returns the maximum difference between succesive points in `pulserecord` after `pulserecord[peak_idx]`
"""
function max_timeseries_deriv_simple(pulserecord, peak_idx)
    max_deriv = typemin(Int)
    for j = peak_idx:length(pulserecord)-1
        deriv = Int(pulserecord[j+1])-Int(pulserecord[j])
        deriv > max_deriv && (max_deriv = deriv)
    end
    max_deriv
end

"Estimate the derivative (units of arbs / sample) for a pulse record or other timeseries.
This version uses the default kernel of [-2,-1,0,1,2]/10.0"
max_timeseries_deriv!(deriv, pulserecord, reject_spikes::Bool) =
    max_timeseries_deriv!(deriv, pulserecord, collect(.2 : -.1 : -.2), reject_spikes)


"Post-peak derivative computed using Savitzky-Golay filter of order 3
and fitting 1 point before...3 points after."
max_timeseries_deriv_SG!(deriv, pulserecord, reject_spikes::Bool) =
    max_timeseries_deriv!(deriv, pulserecord, [-0.11905, .30952, .28572, -.02381, -.45238],
                            reject_spikes)

# Estimate the derivative (units of arbs / sample) for a pulse record or other timeseries.
# Caller pre-allocates the full derivative array, which is available as deriv.
# Returns the maximum value of the derivative.
# The kernel should be a short *convolution* (not correlation) kernel to be convolved
# against the input pulserecord.
# If reject_spikes is true, then the max value at sample i is changed to equal the minimum
# of the values at (i-2, i, i+2). Note that this test only makes sense for kernels of length
# 5 (or less), because only there can it be guaranteed insensitive to unit-length spikes of
# arbitrary amplitude.
#
function max_timeseries_deriv!{T}(
        deriv::Vector{T},       # Modified! Pre-allocate an array of sufficient length
        pulserecord, # The pulse record (presumably starting at the pulse peak)
        kernel::Vector{T},      # The convolution kernel that estimates derivatives
        reject_spikes::Bool  # Whether to employ the spike-rejection test
        )
    N = length(pulserecord)
    Nk = length(kernel)
    @assert length(deriv) >= N+1-Nk
    if Nk > N
        return 0.0
    end
    if Nk+4 > N
        reject_spikes = false
    end
    fill!(deriv, zero(eltype(deriv)))
    for i=1:N-Nk+1
        for j=1:Nk
            deriv[i] += pulserecord[i+Nk-j]*kernel[j] #float
        end
    end
    for i=N-Nk+2:length(deriv)
        deriv[i]=deriv[N-Nk+1]
    end
    if reject_spikes
        for i=3:N-Nk-2
            if deriv[i] > deriv[i+2]
                deriv[i] = deriv[i+2]
            end
            if deriv[i] > deriv[i-2]
                deriv[i] = deriv[i-2]
            end
        end
    end
    maximum(deriv)
end
