using ARMA

function _checkbasis(basis::AbstractMatrix)
    const (N,n) = size(basis)
    n > N && throw(ArgumentError("basis must not have more columns than rows"))

    # Are the columns independent?
    _,r,_ = qr(basis, Val{true})
    if abs(r[end,end] / r[1,1]) < 1e-10
        throw(ArgumentError("basis has (approximately) degenerate columns"))
    end
    N
end

"""
    computeprojectors(basis::AbstractMatrix, noisecovariance::AbstractVector) -> projectors, pcovar

Compute the `projectors` and the projection covariance `pcovar` for the given basis (size=`[N,n]`) and
`noisecovariance`, a vector expressing the noise covariance. Returns a tuple `(projectors,pcovar)`.

The projectors are defined so that if `data` is a vector of length `N`, then

```
coeff = projectors * data
approximation = basis * coeff
```

produces `approximation ≈ data`. Specifically:
1. `approximation` is in the space spanned by the columns of `basis` (by construction), and
1. No other vector in that space is "closer" to `data`, as measured by Mahalanobis
    (signal-to-noise) distance under the model of correlated, additive, Gaussian-distributed
    noise with covariance `noisecovariance`.

`pcovar` is the expected covariance of `coeff` under the same noise assumptions of correlated,
additive, Gaussian noise, independent of the signal levels.
"""
function computeprojectors(basis::AbstractMatrix, noisecovariance::AbstractVector)
    N = _checkbasis(basis)
    length(noisecovariance) < N && throw(ArgumentError("noisecovariance must be at least as long as the basis columns"))
    R = ARMA.toeplitz(noisecovariance[1:N])
    RinvB = R\basis
    if any(isinf.(RinvB))
        throw(DivideError())
    end
    A = basis'*RinvB
    filters = A \ RinvB'
    filters, inv(A)
end

"""
    computeprojectors(basis::AbstractMatrix, noisemodel::ARMA.ARMAModel) -> projectors, pcovar

In this method, the noise is characterized by `noisemodel`, an `ARMAModel` model of the noise covariance.
For large `N` (long basis vectors), this version is likely to consume less time and memory.
"""
function computeprojectors(basis::AbstractMatrix, noisemodel::ARMA.ARMAModel)
    N = _checkbasis(basis)
    solver = ARMASolver(noisemodel, N)
    RinvB = ARMA.solve_covariance(solver, basis)
    if any(isinf.(RinvB))
        throw(DivideError())
    end
    A = basis'*RinvB
    filters = A \ RinvB'
    filters, inv(A)
end
