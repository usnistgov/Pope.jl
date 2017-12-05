using Documenter, Pope

makedocs(
    sitename = "Pope.jl"
)

deploydocs(
    repo   = "github.com/usnistgov/Pope.jl.git",
    osname = "linux",
    julia = "release"
)

println("finished make.jl")
