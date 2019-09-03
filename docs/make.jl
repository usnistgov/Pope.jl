using Documenter, Pope, Pope.LJH

makedocs(
    sitename = "Pope.jl",
    modules = [Pope, LJH],
    format = Documenter.HTML(),
    pages = ["Home" => "index.md",
             "Scripts" => "scripts.md",
             "LJH" => "ljh.md",
             "Pope Internals" => "pope.md",
             "News" => "news.md",
             "Noise Analysis" => "noise.md"
             ]
)

deploydocs(
    repo   = "github.com/usnistgov/Pope.jl.git",
    osname = "linux",
    deps   = nothing,
    target = "build",
    make= nothing
)

println("finished make.jl")
