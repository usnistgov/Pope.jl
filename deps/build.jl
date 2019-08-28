# this is a hack to allow POPE to depend on unregistered Julia Packages
# it should be removed once we understand how to make our own NIST registry.

@info "Running deps/build.jl"
Pkg.add(Pkg.PackageSpec(name="ReferenceMicrocalFiles", PackageSpec(url="https://github.com/ggggggggg/ReferenceMicrocalFiles.jl"))
Pkg.add(Pkg.PackageSpec(name="ARMA", PackageSpec(url="https://github.com/joefowler/ARMA.jl"))

isdir(expanduser("~/.daq")) || mkdir(expanduser("~/.daq"))
