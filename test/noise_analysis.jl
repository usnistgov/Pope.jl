using Base.Test
using ARMA
using HDF5
using Pope: NoiseAnalysis

function compare(m1::ARMAModel, m2::ARMAModel)
    @test m1.p == m2.p
    @test m1.q == m2.q
    @test m1.covarIV ≈ m2.covarIV atol=3e-4 * (2^m1.p)
    @test model_covariance(m1, 50) ≈ model_covariance(m2, 50) atol=3e-4 * (2^m1.p)
end

function compare(m1::NoiseResult, m2::NoiseResult)
    @test m1.autocorr ≈ m2.autocorr
    @test m1.psd ≈ m2.psd
    @test m1.freqstep == m2.freqstep
    @test m1.samplesused == m2.samplesused
    @test m1.datasource == m2.datasource
    compare(m1.model, m2.model)
end

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

        fname1 = tempname()*".hdf5"
        channum = rand(1:99)
        NoiseAnalysis.hdf5save(fname1, channum, noiseresult)
        nr1 = NoiseAnalysis.hdf5load(fname1, channum)
        compare(noiseresult, nr1)

        fname2 = tempname()*".hdf5"
        h5open(fname2, "w") do f
            g1 = g_create(f, "top")
            g2 = g_create(g1, "mid")
            g3 = g_create(g2, "low")
            NoiseAnalysis.hdf5save(g3, noiseresult)
        end
        h5open(fname2, "r") do f
            nr2 = NoiseAnalysis.hdf5load(f["top/mid/low"])
            compare(noiseresult, nr2)
        end
    end
end #testset
