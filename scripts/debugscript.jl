#!/bin/bash
#=
JULIA="${JULIA:-julia}"
JULIA_CMD="${JULIA_CMD:-$JULIA --color=yes --startup-file=no}"
# below gets the directory name of the script, even if there is a symlink involved
# from https://stackoverflow.com/questions/59895/get-the-source-directory-of-a-bash-script-from-within-the-script-itself
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
export JULIA_PROJECT=$DIR/..
export JULIA_LOAD_PATH=@:@stdlib  # exclude default environment
exec $JULIA_CMD -e 'include(popfirst!(ARGS))' "${BASH_SOURCE[0]}" "$@"
=#
tstart = time()
@show get(ENV,"JULIA_PROJECT", nothing)
@show get(ENV,"JULIA_LOAD_PATH", nothing)
println("before using ArgParse ", time()-tstart)
using ArgParse
println("after using ArgParse ",time()-tstart)
s = ArgParseSettings()
@add_arg_table s begin
    "--outputfile", "-o"
        arg_type = String
        help="specify the path of the outputfile, otherwise it will make one up based on pulse_file"

end
println("after add_arg_table ",time()-tstart)
parsed_args = parse_args(ARGS, s)
@show parsed_args
using Pope
println("your other scripts should work! ",time()-tstart)
