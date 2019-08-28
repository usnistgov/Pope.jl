# this is a hack to allow POPE to depend on unregistered Julia Packages
# it should be removed once we understand how to make our own NIST registry.

@info "Running deps/build.jl"
Pkg.develop([
    Pkg.PackageSpec(name="ReferenceMicrocalFiles", url="https://github.com/ggggggggg/ReferenceMicrocalFiles.jl"),
    Pkg.PackageSpec(name="ARMA", url="https://github.com/joefowler/ARMA.jl"),
    ])
