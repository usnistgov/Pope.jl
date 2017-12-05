using Documenter, Pope, Pope.LJH

makedocs(
    sitename = "Pope.jl",
    modules = [Pope, LJH],
    format = :html,
    pages = ["Home" => "index.md",
             "Scripts" => "scripts.md",
             "LJH" => "ljh.md",
             "Pope Internals" => "pope.md",
             "News" => "news.md"
             ]
)

deploydocs(
    repo   = "github.com/usnistgov/Pope.jl.git",
    osname = "linux",
    deps   = nothing,
    julia = "release",
    target = "build",
    make= nothing
)

println("finished make.jl")
