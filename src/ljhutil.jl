
"""Functions for working with LJH file names and the MATTER sentinel file. Intended primarily to easily find all LJH files from the same run,
and to enable compatiblity with Python Mass."""
module LJHUtil

function ljhsplit(ljhname::String)
    if isdir(ljhname)
        dname = ljhname # removes trailing /
        bname = last(split(dname,'/'))
        return dname, bname, ".ljh"
    end
    bname,ext = splitext(basename(ljhname))
    ext = isempty(ext) ? ".ljh" : ext
    m = match(r"_chan\d+", bname)
    dirname(ljhname), m == nothing ? bname : bname[1:m.offset-1], ext
end
function channel(ljhname::String)
    m = match(r"_chan(\d+)", ljhname)
    m == nothing ? -1 : parse(Int,m.captures[1])
end
function fnames(ljhname::String, chans)
    dname, bname, ext = ljhsplit(ljhname)
    [joinpath(dname, "$(bname)_chan$c$ext") for c in chans]
end
function fnames(ljhname::String, c::Int)
    dname, bname, ext = ljhsplit(ljhname)
    joinpath(dname, "$(bname)_chan$c$ext")
end
function allchannels(ljhname::String)
    dname, bname, ext = ljhsplit(ljhname)
    potential_ljh = filter!(s->(startswith(s,bname)), readdir(dname))
    channels = filter!(x->x>=0,[channel(p) for p in potential_ljh])
    sort!(unique(channels))
end
ljhall(ljhname::String) = fnames(ljhname, allchannels(ljhname))
function hdf5_name_from_ljh(ljhnames::String...)
	dname, bname, ext = ljhsplit(ljhnames[1])
	fname = prod([split(f)[2] for f in ljhnames])
	joinpath(dname,hdf5_name_from_ljh(fname))
end
hdf5_name_from_ljh(ljhname::String) = ljhname*"_pope.hdf5"

const sentinel_file_path = joinpath(expanduser("~"),".daq","latest_ljh_pulse.cur")
"matter_writing_status() returns (String, Bool) representing (filename, currently_open)"
function matter_writing_status()
    isfile(sentinel_file_path) || error("$(sentinel_file_path) must be a file")
    open(sentinel_file_path,"r") do sentinel_file
    lines = map(chomp,collect(eachline(sentinel_file)))
    if length(lines)>=1
      return lines[1], length(lines)==1
    else
      return "LJHUtil nonsensical writing status", false
    end
	# the sentinel file has a second line that says closed when it has closed a file
	# so one line means open, two lines means closed
    end
end

"MATTER writes it's writing status to a sentinal file, this emulates matters output for testing purposes.
write_sentinel_file(filename, writingbool), if writingbool is true, it writes that the file is still open.
Will create the `.daq` folder for the sentinel file if it does not already exist."
function write_sentinel_file(filename, writingbool)
    dname = dirname(sentinel_file_path)
    !isdir(dname) && mkdir(dname)
    open(sentinel_file_path,"w") do sentinel_file
        println(sentinel_file,filename)
        if !writingbool
            println(sentinel_file, "closed")
        end
    end
end

"Change the sentinel_file writing status, false->true or true->false."
function change_writing_status()
    fname, writingbool = matter_writing_status()
    write_sentinel_file(fname, !writingbool)
end



end # module
