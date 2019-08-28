using Test
using ARMA
using LinearAlgebra
using Pope

# Tests:
#
# Verify projectors*basis == eye(...)
# Verify both methods give same projectors if noisecovariance is that of the ARMA model.
# Verify projectors and pcovariance scale properly if you scale the basis.
# Verify projectors are the same if you scale the noise model, but pcovariance changes.
# Error if noisecovariance argument is too short.
# Error if basis columns aren't independent.
# Error if noise is zero.
# Error if basis has more columns than rows.

@testset "projections" begin

# Generate a test basis of fixed size, a trivial noise model, and two versions
# of a non-trivial noise model.
(N, n) = 100, 6
basis = randn(N, n)
white = zeros(Float64, N); white[1] = 1.0

model = ARMA.ARMAModel([2.41644, -4.25252, 1.85175], [1, -1.90467, .905899])
covar = ARMA.model_covariance(model, N)

# Compute projections for all three noise models
(wproj,pwcovar) = Pope.computeprojectors(basis, white)
(mproj,pmcovar) = Pope.computeprojectors(basis, model)
(cproj,pccovar) = Pope.computeprojectors(basis, covar)

@testset "core" begin
    # Verify that projecting the basis (for any noise model) yields identity.
    @test wproj*basis ≈ Matrix(1.0I, n, n)
    @test mproj*basis ≈ Matrix(1.0I, n, n)
    @test cproj*basis ≈ Matrix(1.0I, n, n)

    # Verify projecting combinations of the basis works, too.
    # Yes, I realized that success here is implied by the eye(n) tests, above.
    @test cproj*2basis ≈ 2Matrix(1.0I, n, n)
    truecoef = randn(n,n)
    b = basis*truecoef
    @test truecoef ≈ cproj*b

    # Verify both methods give same projectors if noisecovariance is that of the ARMA model.
    @test mproj ≈ cproj

end

@testset "scaling" begin
    # Verify projectors and pcovariance scale properly if you scale the basis.
    (cproj2,pccovar2) = Pope.computeprojectors(2basis, covar)
    @test cproj ≈ 2cproj2
    @test pccovar ≈ 4pccovar2

    # Verify projectors are the same if you scale the noise model, but pcovariance changes.
    (cproj3,pccovar3) = Pope.computeprojectors(basis, 3covar)
    @test cproj ≈ cproj3
    @test 3pccovar ≈ pccovar3
end

@testset "errors" begin
    # Noise input is too short
    @test_throws ArgumentError Pope.computeprojectors(basis, white[1:N-1])

    # Basis vectors are degenerate
    degeneratebasis = copy(basis)
    degeneratebasis[:,end] = sum(degeneratebasis[:,1:3], dims=2)
    @test_throws ArgumentError Pope.computeprojectors(degeneratebasis, white)
    degeneratebasis[:,end] .= 0.0
    @test_throws ArgumentError Pope.computeprojectors(degeneratebasis, white)

    # Noise is zero
    @test_throws SingularException Pope.computeprojectors(basis, 0*white)

    # Basis has more columns than rows
    fatbasis = randn(6, 10)
    @test_throws ArgumentError Pope.computeprojectors(fatbasis, white)

    # @test_throws ErrorException Pope.computeprojectors(fatbasis, white)
end

end
