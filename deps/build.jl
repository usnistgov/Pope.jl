# symlink scripts so we can call via ~/.pope/debugscript.jl
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
    t = joinpath(targetdir, n)
    if isfile(p)
        s = "adding $p $t"
        if isfile(t)
            s*=" (overwriting)"
            @show t
            rm(t)
        end
        println(s)
        open(t,"w") do f
            write(f,"julia $p \$@")
        end
        chmod(t,0o755) # all can rx, user can rwx
    end
end
