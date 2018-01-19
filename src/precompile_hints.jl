cd(joinpath(@__DIR__,"..","test")) do
    # clean out the artifacts directory
    artifacts = joinpath(@__DIR__,"..","test","artifacts")
    isdir(artifacts) && rm(artifacts,recursive=true)
    mkdir(artifacts)

    include(joinpath(@__DIR__,"..","test","noise_analysis.jl"))
    include(joinpath(@__DIR__,"..","test","ljh.jl"))
    include(joinpath(@__DIR__,"..","test","ljh3.jl"))
end
