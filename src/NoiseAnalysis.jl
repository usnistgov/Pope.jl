"""
Tools for the analysis of noise data, including computation of the noise
autocorrelation and power-spectral density.
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
function compute_autocorr(data::AbstractMatrix, nlags::Integer;
        chunk_multiple=7, max_exc=1e99)
    compute_autocorr(vec(data), nlags, chunk_multiple=chunk_multiple, max_exc=max_exc)
end

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

end # module
