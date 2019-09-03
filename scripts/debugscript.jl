#!/usr/bin/env julia --project --color=yes --startup-file=no

tstart = time()
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
