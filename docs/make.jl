using Documenter, Pope, Pope.LJH

makedocs(
    sitename = "Pope.jl",
    modules = [Pope, LJH],
    format = :html,
    html_prettyurls = !("local" in ARGS),
    # Pages = ["Home" => "index.md",
    #          "LJH" => "ljh.md",
    #          "Pope" => "pope.md"
    #          ]
)

deploydocs(
    repo   = "github.com/usnistgov/Pope.jl.git",
    osname = "linux",
    deps   = nothing, #Deps.pip("mkdocs", "python-markdown-math"),
    julia = "release",
    make = ()->nothing # use native html generation
)

println("finished make.jl")
