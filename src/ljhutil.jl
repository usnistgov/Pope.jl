using DataStructures
"""    dir_base_ext(ljhname::AbstractString)
Given an ljh filename like "somedir/a_chan1.ljh" returns ("somedir,")
"""
function dir_base_ext(ljhname::AbstractString)
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
"    channel(ljhname::AbstractString)
Return the Channel number determined from the filename of an ljh file, looks for
the _chan1 part. Returns -1 if not found."
function channel(ljhname::AbstractString)
    m = match(r"_chan(\d+)", ljhname)
    m == nothing ? -1 : parse(Int,m.captures[1])
end
"    fnames(ljhname::AbstractString, chans)
Returns a `Vector{String}` of ljh filenames `ljhname`, but with different
channel numbers one for each channel number in `chans`."
function fnames(ljhname::AbstractString, chans)
    dname, bname, ext = dir_base_ext(ljhname)
    [joinpath(dname, "$(bname)_chan$c$ext") for c in chans]
end
"   fnames(ljhname::AbstractString, c::Int)
Retuns a new ljh filename with channel number `c`."
function fnames(ljhname::AbstractString, c::Int)
    dname, bname, ext = dir_base_ext(ljhname)
    joinpath(dname, "$(bname)_chan$c$ext")
end
"    allchannelnumbers(ljhname::AbstractString)
Returns a sorted `Vector{Int}` containing all the channel numbers of existing
ljh files in the same set as `ljhname`."
function allchannelnumbers(ljhname::AbstractString)
    dname, bname, ext = dir_base_ext(ljhname)
    potential_ljh = filter!(s->(startswith(s,bname)), readdir(dname))
    channels = filter!(x->x>=0,[channel(p) for p in potential_ljh])
    sort!(unique(channels))
end
"    function allchannels(ljhname::AbstractString,maxchannels=typemax(Int))
Returns an `OrderedDict` mapping channel number to filename containing all file
names of existing ljh files in the same set as `ljhname` and all channel numbers.
If there are more than `maxchannels` such files, only the first `maxchannels`
are included."
function allchannels(ljhname::AbstractString,maxchannels=typemax(Int))
    channels = allchannelnumbers(ljhname)
    n = min(length(channels), maxchannels)
    channels = channels[1:n]
    OrderedDict(ch=>fname for (ch,fname) in zip(channels, fnames(ljhname, channels)))
end

function hdf5_name_from_ljh(ljhnames::AbstractString...)
	dname, bname, ext = dir_base_ext(ljhnames[1])
	fname = prod([dir_base_ext(f)[2] for f in ljhnames])
	joinpath(dname,hdf5_name_from_ljh(fname))
end
"    hdf5_name_from_ljh(ljhname::AbstractString)
Returns the filename that pope will use by default for it's output file for a
for a given `ljhname` input."
hdf5_name_from_ljh(ljhname::AbstractString) = ljhname*"_pope.hdf5"

const sentinel_file_path = joinpath(expanduser("~"),".daq","latest_ljh_pulse.cur")
"    matter_writing_status()
returns a tuple (String, Bool) representing (filename, currently_open)"
function matter_writing_status()
    isfile(sentinel_file_path) || error("$(sentinel_file_path) must be a file")
    open(sentinel_file_path,"r") do sentinel_file
    lines = map(chomp,collect(eachline(sentinel_file)))
    if length(lines)>=1
      return lines[1], length(lines)==1
    else
      return "empty sentinel file", false
    end
	# the sentinel file has a second line that says closed when it has closed a file
	# so one line means open, two lines means closed
    end
end

"    write_sentinel_file(filename, writingbool)
MATTER writes it's writing status to a sentinal file, this emulates matters output for testing purposes.
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

"    change_writing_status()
Change the sentinel_file writing status, false->true or true->false."
function change_writing_status()
    fname, writingbool = matter_writing_status()
    write_sentinel_file(fname, !writingbool)
end
