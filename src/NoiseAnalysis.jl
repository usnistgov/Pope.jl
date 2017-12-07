"""
Tools for the analysis of noise data, including computation of the noise
autocorrelation and power-spectral density.

Power spectra require a window function. We suggest `NoiseAnalysis.bartlett` as
a default. Package DSP.jl has many others in module `DSP.Windows`.
"""
module NoiseAnalysis

export compute_autocorr

"""
    round_up_dft_length(n)

A length at least as large as `n` convenient for a DFT: (1, 3, or 5) x any power
of 2. This ensures that we never do DFTs on an especially bad vector size.
"""
function round_up_dft_length(n::Integer)
    pow2 = 2^ceil(log2(n))
    if n > 0.75*pow2
        return Int(round(pow2))
    elseif n > 0.625*pow2
        return Int(round(0.75*pow2))
    else
        return Int(round(0.625*pow2))
    end
end


"""
    compute_autocorr(data, nlags; chunk_multiple, max_exc)

Compute the autocorrelation function of the data, for lags `0:nlags-1`.

It is assumed that the length of the data vector is much greater than the
number of lags desired and that the data values are continuous (no gaps).

Group the data into segments of lengths `nlags*chunk_multiple` before computing
autocorrelation, so as to have significant number of samples at the maximum lag.
Typically any `chunk_multiple` of at least 3 should be fine (default = 7). In
any chunk, if the extreme value deviates by more than `max_exc` from the mean
value in either direction, the chunk will not be used. By default, `max_exc` is
large (1e99), but it is smart to set it to a more reasonable value for your
application.
"""
compute_autocorr(data::AbstractMatrix, nlags::Integer; kwargs...) =
    compute_autocorr(vec(data), nlags; kwargs)

function compute_autocorr(data::AbstractVector, nlags::Integer;
        chunk_multiple=7, max_exc=1e99)
    m = nlags*chunk_multiple
    nseg = div(length(data), m)

    # Pad the raw data with at least nlags zeros, but also additional ones to ensure
    # that the DFT isn't taken on an unfortunately long and inefficient size.
    m_padded = round_up_dft_length(m+nlags)
    padded_data = zeros(Float64, m_padded)
    ac = zeros(Float64, nlags)

    # This loop uses all data except the last length(data) % m values.
    seg_skipped = 0
    for i=1:nseg
        seg = float(data[(i-1)*m+1:i*m])
        padded_data[1:m] = seg - mean(seg)
        if maximum(abs.(padded_data[1:m])) > max_exc
            seg_skipped += 1
            continue
        end
        r = rfft(padded_data)
        ac += irfft(abs2.(r), m_padded)[1:nlags]
    end
    ac /= (nseg-seg_skipped)
    ac ./ (m:-1:m-nlags+1)
end

# Power spectra and window functions:
"""
    bartlett(n)

Bartlett window of length `n`.
"""
function bartlett(n::Integer)
    [(1 - abs(k*2/(n-1) - 1)) for k=0:(n-1)]
end

"""
    welch(n)

Welch window of length `n`.
"""
function welch(n::Integer)
    [(1 - ((k*2/(n-1)) - 1)^2) for k=0:(n-1)]
end

"""
    hann(n)

Hann window of length `n`.
"""
function hann(n::Integer)
    [1-cos(2π*k/(n-1)) for k=0:(n-1)]
end

# See package DSP.jl with module DSP.Windows for more window functions.

"""
    compute_psd(data, nfreq, dt)

Compute the Power-Spectral Density of `data`, which was sampled at
equal time steps of size `dt`, at `nfreq` frequencies equal to
`fsamp = linspace(0, 0.5/dt, nfreq)`. Generally, you want `nfreq` to be
1 more than a power of 2, and you need `nfreq ≤ div(1+length(data), 2)`
(ideally, much less than).

The `data` are assumed to be a continuous sequence of noise samples.
Use overlapping segments of the exact needed length (`2(nfreq-1)`), offset by
approximately half their length.
"""
compute_psd(data::AbstractArray, nfreq::Integer, dt::Real; kwargs...) =
    compute_psd(vec(data), nfreq, dt; kwargs)

function compute_psd(data::AbstractVector, nfreq::Integer, dt::Real; max_exc=1e99)

    nsamp = 2(nfreq-1)
    if length(data) < nsamp
        error("data must be at least 2(nfreq-1) in length.")
    end

    # If you have any appreciable power at DC and wish to understand the low-freq
    # power spectrum, you want the hann window or no window, because only these
    # have zero leakage for bins 3:end (zero leakage into bin 2, also, if using
    # no window at all).
    window = hann(nsamp)
    window = window / sqrt(sum(window.^2)) # proper normalization

    # Break data up into half-overlapping segments of the right separation
    nseg = Int(ceil(length(data)/nsamp))
    seg_step = 1
    if nseg>1
        seg_step = Int(floor((length(data)+1-nsamp)/(nseg-1)))
    end

    r = zeros(Float64, nfreq)
    datamean = mean(data)
    for i=1:nseg
        idx0 = (i-1)*seg_step+1
        seg = window .* (data[idx0:idx0+nsamp-1] - datamean)
        r += abs2.(rfft(seg))
    end
    r * 2dt / nseg
end

psd_freq(nfreq::Integer, dt::Real) = linspace(0, 0.5/dt, nfreq)

end # module
