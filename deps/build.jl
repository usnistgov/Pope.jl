# this is a hack to allow POPE to depend on unregistered Julia Packages
# it should be removed if/when there is an official way of doing this other
# than maintaining and using my own copy of METADATA

if !isdir(Pkg.dir("ReferenceMicrocalFiles"))
	Pkg.clone("https://github.com/ggggggggg/ReferenceMicrocalFiles.jl")
end
if !isdir(Pkg.dir("ARMA"))
	Pkg.clone("https://github.com/joefowler/ARMA.jl")
end

isdir(expanduser("~/.daq")) || mkdir(expanduser("~/.daq"))
