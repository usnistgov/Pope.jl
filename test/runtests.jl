using Pope.LJH
using HDF5
using Test
const WT = false # run @code_warntype

# clean out the artifacts directory
isdir("artifacts") && rm("artifacts",recursive=true)
mkdir("artifacts")

include("noise_analysis.jl")
include("ljh.jl")
include("ljh3.jl")
include("ljhutil.jl")
include("pope.jl")
include("basis_apply.jl")
include("projections.jl")
include("basis_creation.jl")
