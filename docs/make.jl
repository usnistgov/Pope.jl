using Documenter, Pope

makedocs(
    format = :html,
    sitename = "Pope.jl"
    )

deploydocs(
    repo   = "github.com/usnistgov/Pope.jl.git",
    target = "pope",
    deps   = nothing,
    osname = "osx",
    julia = "release"
)
