using jcomp
using Documenter

DocMeta.setdocmeta!(jcomp, :DocTestSetup, :(using jcomp); recursive=true)

makedocs(;
    modules=[jcomp],
    authors="xoth42 <xoth42@protonmail.com> and contributors",
    repo="https://github.com/xoth42/jcomp.jl/blob/{commit}{path}#{line}",
    sitename="jcomp.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://xoth42.github.io/jcomp.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/xoth42/jcomp.jl",
)
