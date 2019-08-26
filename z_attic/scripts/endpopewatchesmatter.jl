#!/usr/bin/env julia
using DocOpt
using Pope: LJH
doc = """
End Pope Watches Matter
This will write info to the matter sentinel file that will cause popewatches matter to end, if it it waiting on that file.

Usage:
  endpopewatchesmatter.jl
"""

arguments = docopt(doc, version=v"0.0.1")
LJH.write_sentinel_file("endpope",true)
println("End Pope Watches Matter wrote sentinel file: endpope, true")
sleep(1)
LJH.write_sentinel_file("endpope",false)
println("End Pope Watches Matter wrote sentinel file: endpope, false")
