#!/usr/bin/julia
# Todo Testing
module jcompWrapper

using PackageCompiler, Comonicon, Dates, Pkg, ShareAdd

# Constants
const DEFAULT_DIR = "$(ENV["HOME"])/.julia/sysimages"
const NOW = Dates.now()
const JCOMP_TMP = "/tmp/jcomp"
"""

jcomp: configure and compile julia sysimages for you.

# Args

- `env`: julia enviroment that the sysimage is being created for (will use the Pkg.activate default if not supplied).
# Options

- `-p, --precompile-trace=<path>`: precompile statements file for sysimage creation.
- `-e, --exclude=<list>`: comma seperated list (ex. Package1,Pack2,Mypack,keyword) of packages to exclude from sysimage creation, exclude any line in a trace file (if supplied) that contains anything from this list.
- `-n, --name=<sysimage1.so>`: specify path for output sysimage, defaults to jcomp-$(NOW)-sysimage.so.
- `--sysimg-dir=<path>`: location for output sysimage files, defaults to $(DEFAULT_DIR).
- `-t, --threads=<int>`: Threads to supply for the compilation, default is auto
- `-b, --base-sysimage=<name>`: sysimage to build this one on top of (recommended if you have another sysimage)
# Flags
- `-v, --verbose`: verbose output.
- `--debug`: print additional debugging information 
- `--no-inst`: do not call Pkg.instantiate() in the target directory
- `--stdout`: print only the final script 
"""
@Comonicon.main function jcomp(env=nothing;
    precompile_trace=nothing,
    exclude=nothing,
    name="jcomp-$(NOW)-sysimage.so",
    sysimg_dir=DEFAULT_DIR,
    threads="auto",
    base_sysimage=nothing,
    verbose::Bool=false,
    debug::Bool=false,
    no_inst::Bool=false,
    stdout::Bool=false
)
    try # global try for dealing with ctrl-c or general errs
    
    #### Check for argument/config issues
    # try ENV["HOME"]; catch # Make sure the user has a proper enviroment
    #     println("\$HOME not set. Please set \$HOME") 
    #     exit(1)
    # end
    if !isdir("$(ENV["HOME"])/.julia") # No julia directory
        println("~/.julia not found. Please install julia")
        exit(1)
    end
    # check if jcomp_dir is set
    try ENV["JCOMP_ENV"] catch
        println("Please set JCOMP_ENV")
        exit(1)
    end

    # Make sure env is there
    _env = env # local variable to make editable
    if isnothing(env) 
        # env is not set
        cmd_pwd = pwd()
        _env = cmd_pwd # default to local env
    elseif !isdir(env) 
        # env is set, but not a directory 
        println("Enviroment $env not found")
        exit(1)
    end

    # Check if the trace file is there
    trace = precompile_trace  # local var so it is editable

    if !isfile(precompile_trace) && !isnothing(precompile_trace) # full path 
        jp = ""
        try
            verbose && println("""jp = joinpath([_envprecompile_trace])""")
            # jp = joinpath([_env,precompile_trace])
            jp = _env * "/" * precompile_trace
        catch err
            println("joinpath err: $err")
            exit(1)
        end
        if isfile(jp) # Check instead if they mean a local file
            trace = jp # local trace file found, use it
            !stdout && verbose && println("Using the local tracefile: $trace")
        else
            # could not find it either way
            println("trace file $precompile_trace not found")
            exit(1)
        end
    end

    # Check for, and make if needed sysimage directory
    if isdir(sysimg_dir)
        !stdout && verbose && print("Sysimg dir $(sysimg_dir) found\n")
    else
        !stdout && println("Sysimage directory not found, making one now at $sysimg_dir")
        mkdir(sysimg_dir)
    end

    # Check the base_sysimage
    if !isnothing(base_sysimage) && !isfile(base_sysimage)
        println("Base sysimage $base_sysimage not found")
        exit(1)
    end
        
    # For debugging params, cmd usage
    if debug && !stdout
        println("JCOMP_ENV: $(ENV["JCOMP_ENV"])")
        println("Pwd: $(pwd())")
        println("Args:")
        println("  j_env: $(env)")
        println("  trace: $(trace)")
        println("  exclude: $(exclude)")
        println("  name: $(name)")
        println("  dir: $(sysimg_dir)")
        println("  verbose: $(verbose)")
    end

    ### Get the packages needed for compilation
    # Init env for packages
    !stdout && println("Activating $(_env) julia enviroment")
    !stdout && verbose && println("""Pkg.activate("$(_env)")""")
    _ = Pkg.activate(_env);
    
    # Instantiate target project
    if !no_inst
        !stdout && verbose && println("Pkg.instantiate()")
        try
            Pkg.instantiate()
        catch error
            if isa(error, SystemError)
                println("No julia enviroment found at $_env")
                exit(0)
            end
            println("Error instantiating enviroment at $_env")
            println(error)
            
            exit(1)
        end
    end

    # get packages
    packages::Vector{String} = collect(ShareAdd.current_env().pkgs)
    !stdout && verbose && println("Found packages: $(packages)")
    # remove excluded if present
    ex_list = nothing
    if !isnothing(exclude)
        ex_list = split(exclude,",")
        filterExcludedPhrases!(packages,ex_list)
        !stdout && verbose && println("Packages excluded, now: $(packages)")
    end

    # edgecase, no packages to compile 
    if length(packages) == 0
        println("No packages to compile, exiting...")
        exit()
    end

    ### Prepare compilation command
    # return back to jcomp enviroment
    !stdout && verbose && println("Returning back to original enviroment")
    _ = Pkg.activate(ENV["JCOMP_ENV"]);

    # define sysimg creation function 
    sysimg_config = "project=\"$(_env)\",sysimage_path=\"$(sysimg_dir)/$(name)\"" * (isnothing(base_sysimage) ? "" : ",base_sysimage=\"$base_sysimage\"")
    sysimg_cmd = """Creating sysimage file: PackageCompiler.create_sysimage($(packages);$sysimg_config)"""
    function start_sysimg()
        out = "$JCOMP_TMP/jcomp-$NOW"
        out_last = "$JCOMP_TMP/jcomp-last"

        # verbose && println("Starting subprocess to create sysimg")
        script = "using Pkg;Pkg.instantiate();using PackageCompiler; println(\"Starting sysimg creation\");PackageCompiler.create_sysimage($packages; $sysimg_config)"
        cmd = """#!/bin/sh\n# Generated by jcomp\n$(Sys.BINDIR)/julia -t$(threads == "auto" ? "auto,auto" : " $threads") --project=\'$(_env)\' -e '$(script)' \n"""
        verbose && println(`$(cmd)`)
        if !stdout # if not only printing cmd to stdout
            verbose && println("Sending command to $out")
            try
                cd(readdir,JCOMP_TMP)
            catch
                mkdir(JCOMP_TMP)
            end

            # Write cmd to /tmp/jcomp/jcomp-(current time), 
            out = "$JCOMP_TMP/jcomp-$NOW"
            io = open(out, "w")
            write(io,cmd)
            close(io)
            # and to /tmp/jcomp/jcomp-last
            out_last = "$JCOMP_TMP/jcomp-last"
            io = open(out_last, "w")
            write(io,cmd)
            close(io)
        
            # Making the files executable
            run(`/bin/chmod +x $out`)
            run(`/bin/chmod +x $out_last`)

            println("\nTo start the compiler, run:\n$out_last")
        end
    end

    # see if a tracefile was specified
    if !isnothing(trace) 
        # filter tracefile if needed, make sysimage
        if !isnothing(exclude)
            # trace present, and exclusion present
           
            # get the original trace file
            io = open(trace, "r")
            trace_statements = split(read(io,String),'\n')

            close(io)
            debug && println("Read trace file $trace: $trace_statements")

            # filter it as requested
            filterExcludedPhrases!(trace_statements,ex_list)
            debug && println("Filtered trace file: $trace_statements")

            # write the filtered file
            # Make a temp dir for the output filtered tracefile
            excluded_trace_dir = tempname()
            mkdir(excluded_trace_dir)

            # the file we will write to is tmpdir/trace.jl
            f = ""
            try
                verbose && println("""joinpath([excluded_trace_dir,"trace.jl"])""")
                # f = joinpath([excluded_trace_dir,"trace.jl"])
                f = excluded_trace_dir * "/" * "trace.jl"
            catch err
                println("Joinpath err: $err")
                exit(1)
            end
            !stdout && verbose && println("Filtering trace file, outputting to $f")
            io = open(f, "w")
            write(io,trace_statements...)
            close(io)
            
            trace = f
        end

        # create sysimage with trace file
        sysimg_config *= ",precompile_statements_file=\"$trace\"" # add the trace specification 
        sysimg_cmd = """Creating sysimage file: PackageCompiler.create_sysimage($(packages);$sysimg_config)"""
    end
    
    # Start sysimg creation
    !stdout && verbose && println(sysimg_cmd)
    # Print what packages will be compiled
    !stdout && length(packages) == 1 ? println("Package to compile:
    $(packages[1])") : 
    # Print what packages will be compiled
    !stdout && println("Packages to compile:\n$(reduce((x,y)->x*", "*y,packages[2:end];init=packages[1]))")
    
    try
        start_sysimg()
    catch err
        println("Error making sysimage")
        throw(err )
    end

    # Verify sysimage creation
    # (verbose) && println("Verifying sysimage creation")
    #     verify = run(`file $(dir)/$(name)`)
    #     if contains("cannot open",verify)
    #         println("sysimage creation failed")
    #     else
    #         println("Sysimage created at $(dir)/$(name)")
    #     end

    catch err
        if isa(err,InterruptException)
            println("\nExiting...")
            exit()
        else
            verbose && println("\n$(err)")
            exit()
        end
    end

end

"""
    lineContains(line::String,contents::Vector{String})

    Helper to check if a line contains any of the strings in a list.
    returns true if the line contains any strings in the contents array
"""
function lineContains(line::T where T <: AbstractString,contents::Vector{<: AbstractString})
    for item in contents
        if contains(line,item)
            return true
        end
    end
    return false
end

function lineContains(line::T where T <: AbstractString, contents::R where R <: AbstractString) 
    return contains(line, contents)
end

"""
    filterExcludedPhrases!(arr::Vector{String},excluded_phrases::Vector{String})

calls filter!() on the array, filtering out any lines that contain any of the phrases in excluded_phrases.
"""
function filterExcludedPhrases!(arr::Vector{<:AbstractString},excluded_phrases::Vector{<:AbstractString})
    filter!(line->!lineContains(line,excluded_phrases),arr)
end

end