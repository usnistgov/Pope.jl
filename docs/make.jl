using Documenter, Pope

makedocs(
    sitename = "Pope.jl"
)

deploydocs(
    repo   = "github.com/usnistgov/Pope.jl.git",
    osname = "linux",
    deps   = Deps.pip("mkdocs", "python-markdown-math"),
    julia = "release"
)

println("finished make.jl")
