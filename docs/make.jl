using Documenter, Pope, Pope.LJH

makedocs(
    sitename = "Pope.jl",
    modules = [Pope, LJH],
    # format = :html,
)

deploydocs(
    repo   = "github.com/usnistgov/Pope.jl.git",
    osname = "linux",
    deps   = Deps.pip("mkdocs", "python-markdown-math"),
    julia = "release"
)

println("finished make.jl")
