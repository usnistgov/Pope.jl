#!/bin/bash
#=
JULIA="${JULIA:-julia}"
JULIA_CMD="${JULIA_CMD:-$JULIA --color=yes --startup-file=no}"
export JULIA_PROJECT="$(pwd)/$JULIA_PROJECT.."
export JULIA_LOAD_PATH=@:@stdlib  # exclude default environment
exec $JULIA_CMD -e 'include(popfirst!(ARGS))' "${BASH_SOURCE[0]}" "$@"
=#
@show ENV["JULIA_PROJECT"]
@show ENV["JULIA_LOAD_PATH"]
using ArgParse
s = ArgParseSettings()
@add_arg_table s begin
    "--outputfile", "-o"
        arg_type = String
        help="specify the path of the outputfile, otherwise it will make one up based on pulse_file"

end
parsed_args = parse_args(ARGS, s)
println(parsed_args)
using Pope
println("your other scripts should work!")
