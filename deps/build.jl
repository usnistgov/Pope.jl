# copy scripts to ~/.pope
println("running Pope/build.jl")
scriptsdir = normpath(joinpath(@__DIR__, "..", "scripts"))
targetdir = expanduser("~/.pope")
if !isdir(targetdir)
    println("creating $targetdir")
    mkdir(targetdir)
end
@show scriptsdir
@show targetdir
for n in readdir(scriptsdir)
    p = joinpath(scriptsdir, n)
    if isfile(p)
        s = "copying $(basename(n)) to $targetdir"
        if isfile(p)
            s*=" (overwriting)"
        end
        println(s)
        cp(p, joinpath(targetdir,n), force=true)
    end
end
