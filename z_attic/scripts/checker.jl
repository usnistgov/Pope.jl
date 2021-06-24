#!/usr/bin/env julia
using HDF5, DataStructures
using Pope: LJH
using DocOpt

doc = """
Pope Checker
Used to find folders where pope analysis didn't work quite right and re-run pope on them. Provide a <dir> to look for ljh containing directories in, and if you want the option to reanalyze the files, provide <pkfilename>. You will have a chance to review the candidates, and review the proposed commands, before anything actually happens. At most this will make a file checker.sh, which you can then run via bash checker.sh.
Usage:
	checker.jl [--missing_hdf5_is_candidate] <dir> [<pkfilename>]

Options:
	--missing_hdf5_is_candidate       Folders that lack a pope hdf5 file algtogther are not considered reanalysis candidates unless you provide this flag.
"""

immutable FolderStatus
	n_ljh_file::Int
	pope_hdf5_found::Bool
	n_channels_in_hdf5::Int
	n_channels_in_hdf5_matching_ljh_found::Int
	n_channels_hdf5_and_ljh_match_length::Int
	n_channels_filt_value_nonzero::Int
end
function Base.show(io::IO,fs::FolderStatus)
	if fs.pope_hdf5_found
		print(io, "$(fs.n_ljh_file) ljh files found, $(fs.n_channels_in_hdf5) channels in hdf5, $(fs.n_channels_in_hdf5_matching_ljh_found) channels match between ljh and hdf5, $(fs.n_channels_hdf5_and_ljh_match_length) channels have matching lengths. $(fs.n_channels_filt_value_nonzero) have nonzero first filt_value.")
	else
		print(io, "$(fs.n_ljh_file) ljh files found, no pope hdf5 found.")
	end
end



function get_pope_hdf5_fname(dir)
	a=filter(x->contains(x,"pope"),readdir(dir))
	if length(a) == 1
		Nullable(joinpath(dir,a[1]))
	else
		Nullable{String}()
	end
end

function comparechannels(popefilename, ljhdict,verbose)
	nchannels = 0
	nchannelsmatchlength = 0
	nchannelsfiltvaluenonzero = 0
	p = h5open(popefilename,"r")
	n_hdf5_channel = length(filter(s->startswith(s,"chan"),keys(p)))
	for ch in 1:2:480
		chanstr = "chan$ch"
		ch in keys(ljhdict) || continue
		exists(p,chanstr) || continue
		nchannels+=1
		chan = p[chanstr]
		ljh = Pope.LJH.LJHFile(ljhdict[ch])
		if length(chan["filt_value"]) == length(ljh)
			nchannelsmatchlength+=1
		elseif verbose
			println("$chanstr pope_hdf5 has $(length(chan["filt_value"])) length, $(ljh.filename) has $(length(ljh))")
		end
		chan["filt_value"][1] !=0 && (nchannelsfiltvaluenonzero+=1)
	close(ljh)
	end
	close(p)
	return FolderStatus(length(ljhdict), true, n_hdf5_channel, nchannels, nchannelsmatchlength, nchannelsfiltvaluenonzero)
end


"comparechannels(d;verbose=false)
Look in directory `d` for a pope hdf5 file, and return a FolderStatus object containing info used to determine if the folder is a re-analysis candidate."
function comparechannels(d;verbose=false)
	pope_hdf5_nullable = get_pope_hdf5_fname(d)
	ljhdict = LJH.allchannels(d)
	if isnull(pope_hdf5_nullable)
		return FolderStatus(length(ljhdict), false, 0, 0, 0, 0)
	else
 		return comparechannels(get(pope_hdf5_nullable), ljhdict,verbose)
	end
end
function is_renalysis_candidate(f::FolderStatus, missing_hdf5_is_candidate::Bool)
	f.n_ljh_file==0 && return false
	!f.pope_hdf5_found && return missing_hdf5_is_candidate
	return f.n_channels_hdf5_and_ljh_match_length != f.n_channels_in_hdf5_matching_ljh_found
end

#test for is_reanalysis_candidate
# missing_hdf5_is_candidate
@assert !is_renalysis_candidate(FolderStatus(1,false,1,1,1,1), false)
@assert is_renalysis_candidate(FolderStatus(1,false,1,1,1,1), true)
# must have at least 1 ljh file
@assert !is_renalysis_candidate(FolderStatus(0,false,1,1,1,1), true)
@assert !is_renalysis_candidate(FolderStatus(0,true,1,1,1,1), true)
# length match (4th and 5th arguments match)
@assert !is_renalysis_candidate(FolderStatus(1,true,1,1,1,1), true)
@assert is_renalysis_candidate(FolderStatus(1,true,1,1,0,1), true)

function get_reanalysis_candidates(dirs, missing_hdf5_is_candidate::Bool, verbose::Bool)
	fsdict = OrderedDict(collect(d=>comparechannels(d,verbose=verbose) for d in dirs))
	filter((k,v)-> is_renalysis_candidate(v,missing_hdf5_is_candidate),fsdict)
end

function report_candidates(fsdict)
	println("Review these $(length(fsdict)) re-analysis candidates (must have ljh files in them, also depends on --missing_hdf5_is_candidate flag):")
	for (k,v) in fsdict
		println("$k")
		println("\tWhy? $v")
	end
end

function prompt_yes_no(s;exit_on_no=false)
	while true
		println(s)
		print("[y/n]?")
		r = lowercase(chomp(readline()))
		if startswith("yes",r) && length(r)>0
			return true
		elseif startswith("no",r) && length(r)>0
			if exit_on_no
				exit()
			else
				return false
			end
		end
	end
end

function make_reanalysis_command(pkfilename, candidate)
	k,v=candidate
	chan1 = LJH.fnames(k,1)
	outputpath = LJH.hdf5_name_from_ljh(chan1)
	"./popeonce.jl --overwriteoutput $k $pkfilename $outputpath"
end

arguments = docopt(doc, version=v"0.0.1")

missing_hdf5_is_candidate = arguments["--missing_hdf5_is_candidate"]
pkfilename = arguments["<pkfilename>"] # nothing if missing, String if input
startdir = arguments["<dir>"]
println("Searching $startdir")
lscmd = `ls $startdir`
println(lscmd)
println(chomp(readstring(lscmd)))
searchdirslocal = [d for d in readdir(startdir) if isdir(joinpath(startdir,d))]
searchdirs = [joinpath(startdir,d) for d in searchdirslocal]
println("Found $(length(searchdirs)) subdirs")
candidates = get_reanalysis_candidates(searchdirs,missing_hdf5_is_candidate,false)
#for (k,v) in candidates
#	println(k)
#	iscandidate = is_renalysis_candidate(v,missing_hdf5_is_candidate)
#	println("Is candidate? $iscandidate")
#	println(v)
#end
report_candidates(candidates)
println("Preknowledge filename: $pkfilename")
commands = collect(make_reanalysis_command("$pkfilename",c) for c in candidates)
prompt_yes_no("Should this program proceed to renalyze all shown candidates?",exit_on_no=true)
prompt_yes_no("Use preknowledge file: $pkfilename?",exit_on_no=true)
println("Proposed Commands")
for c in commands println(c) end
if pkfilename == nothing
	println("You must pass pkfilename to re-analyze, commands show have nothing as a stand in name.")
	exit()
end
prompt_yes_no("Do the proposed commands look ok?", exit_on_no=true)
println("Writing proposed commands to checker.sh. You can do `bash checker.sh to execute them.")
open("checker.sh","w") do f
for c in commands write(f,string(c)*"\n") end
end
