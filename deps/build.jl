# this is a hack to allow POPE to depend on unregistered Julia Packages
# it should be removed once we understand how to make our own NIST registry.

print("Running deps/build.jl")
try
	import ReferenceMicrocalFiles
catch
	Pkg.add(PackageSpec(url="https://github.com/ggggggggg/ReferenceMicrocalFiles.jl"))
end
try
	import ARMA
catch
	Pkg.add(PackageSpec(url="https://github.com/joefowler/ARMA.jl"))
end

isdir(expanduser("~/.daq")) || mkdir(expanduser("~/.daq"))
