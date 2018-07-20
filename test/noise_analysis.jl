using Base.Test
using ARMA
using HDF5
using Pope: NoiseAnalysis
import Base: isapprox

isapprox(m1::ARMAModel, m2::ARMAModel) =
    (m1.p == m2.p) && (m1.q == m2.q) &&
    isapprox(m1.covarIV, m2.covarIV, atol=3e-4 * (2^m1.p)) &&
    isapprox(model_covariance(m1, 50), model_covariance(m2, 50), atol=3e-4 * (2^m1.p))

isapprox(m1::NoiseResult, m2::NoiseResult) =
    (m1.autocorr ≈ m2.autocorr) && (m1.psd ≈ m2.psd) &&
    (m1.freqstep == m2.freqstep) && (m1.samplesused == m2.samplesused) &&
    (m1.datasource == m2.datasource) && (m1.model ≈ m2.model)

@testset "hdf5 save/load" begin
    # Here are some dummy values to fill in the NoiseResult.
    used = 100000 # info about how many data samples were studied
    sampletime = 2e-5
    source = "not_actually_a_file.ljh"

    ntests = 5
    for i = 1:ntests
        nbases = rand(2:6)
        bases = rand(nbases)
        ampls = 10*rand(nbases)
        covarIV = [3*sum(abs.(ampls))]
        model = ARMAModel(bases, ampls, covarIV)
        acorr = ARMA.model_covariance(model, 500)
        psd = ARMA.model_psd(model, 300)
        freqstep = 0.5/sampletime / (length(psd)-1)
        noiseresult = NoiseAnalysis.NoiseResult(acorr, psd, used, freqstep, source, model)

        # Test loading from the "standard place" in a file, which depends on channel number
        fname1 = tempname()*".hdf5"
        channum = rand(1:99)
        NoiseAnalysis.hdf5save(h5open(fname1,"w"), channum, noiseresult)
        nr1 = NoiseAnalysis.hdf5load(fname1, channum)
        @test noiseresult ≈ nr1

        # Test loading from a user-specified group within a fil.
        fname2 = tempname()*".hdf5"
        h5open(fname2, "w") do f
            g1 = g_create(f, "top")
            g2 = g_create(g1, "mid")
            g3 = g_create(g2, "low")
            NoiseAnalysis.hdf5save(g3, noiseresult)
        end
        h5open(fname2, "r") do f
            nr2 = NoiseAnalysis.hdf5load(f["top/mid/low"])
            @test noiseresult ≈ nr2
        end
    end
end #testset
