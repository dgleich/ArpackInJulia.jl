## This needs to be loaded AFTER arpackjll.jl

#= Here is the idea, we dispatch on ArpackState to forward
the same call to our Julia routine as well as the Arpack
routine and check that we have exactly the same result! 

Note that this can be tricky because of ARPACK State. You
must override only one of dsaupd2, dsaitr, dgetv0. Because...
- dsaupd2 calls dsaitr, dgetv0 
- dsaitr calls dgetv0
Although they may be situations where you can call them separately.
But beware the random seed info in dgetv0 and use
_reset_libarpack_dgetv0_iseed if needed... 
=#
module CheckWithArpackjll
  using Test
  using ArpackInJulia
  import ArpackInJulia: AitrState, Getv0State, Saup2State, AbstractArpackState
  using LinearAlgebra

  Base.@kwdef mutable struct ArpackjllState{T} <: AbstractArpackState{T}
    aitr::AitrState{T} = AitrState{T}()
    getv0::Getv0State{T} = Getv0State{T}()
    saup2::Saup2State{T} = Saup2State{T}()
    aupd_nev0 = Ref{Int}(0)
    aupd_np = Ref{Int}(0)
    aupd_mxiter = Ref{Int}(0)

    handle_saitr::Symbol = :use
    handle_saup2::Symbol = :use
    handle_getv0::Symbol = :use
  end 

  function dsaup2(
    ido::Ref{Int}, 
    ::Val{BMAT},
    n::Int,
    which::Symbol,
    nev::Ref{Int},
    np::Ref{Int}, 
    tol::T,
    resid::AbstractVecOrMat{T},
    mode::Int, 
    iupd::Int,
    ishift::Int,
    mxiter::Ref{Int},
    V::AbstractMatrix{T},
    ldv::Int, 
    H::AbstractMatrix{T}, 
    ldh::Int,
    ritz::AbstractVecOrMat{T},
    bounds::AbstractVecOrMat{T},
    Q::AbstractMatrix{T},
    ldq::Int, 
    workl::AbstractVecOrMat{T},
    ipntr::AbstractVecOrMat{Int},
    workd::AbstractVecOrMat{T},
    info_initv0::Int, # info in Arpack, but we return info... 
    state::ArpackjllState{T}
    ;
    stats::Union{ArpackStats,Nothing}=nothing,
    debug::Union{ArpackDebug,Nothing}=nothing,
    idonow::Union{ArpackOp,Nothing}=nothing
  ) where {T, BMAT}
    # these codes won't work with idonow. 
    @assert idonow === nothing 
    normalstate = ArpackInJulia.ArpackState{T}()
    normalstate.getv0 = state.getv0

    if state.handle_saup2 == :use
      return Main.arpack_dsaup2(ido, BMAT, n, which, nev, np, tol, resid, mode,
        iupd, ishift, mxiter, V, ldv, H, ldh, ritz, bounds, Q, ldq, 
        workl, ipntr, workd, info_initv0
      )
    elseif state.handle_saup2 == :check
      @error("Shouldn't get here. state.handle_saup2 = $(state.handle_saup2) ':check'")
    else
      # just pass this one...
    end
  end 

  function ArpackInJulia.dgetv0!(
    ido::Ref{Int}, # input/output
    ::Val{BMAT},
    itry::Int, # input
    initv::Bool,
    n::Int,
    j::Int,
    V::AbstractMatrix{T},
    ldv::Int, # TODO, try and remove
    resid::AbstractVecOrMat{T},
    rnorm::Ref{T}, # output
    ipntr::AbstractVector{Int}, # output
    workd::AbstractVector{T}, # output
    state::ArpackjllState{T};
    stats::Union{ArpackInJulia.ArpackStats,Nothing}=nothing,
    debug::Union{ArpackInJulia.ArpackDebug,Nothing}=nothing,
    idonow::Union{ArpackInJulia.ArpackOp,Nothing}=nothing
    ) where {T, BMAT}

    normalstate = ArpackInJulia.ArpackState{T}()
    normalstate.getv0 = state.getv0

    if state.handle_getv0 == :use
      # verify the type
      @assert typeof(resid) <: StridedVecOrMat{T}
      @assert typeof(V) <: StridedMatrix{T}
      @assert typeof(workd) <: StridedVecOrMat{T}
      @assert typeof(ipntr) <: StridedVecOrMat{LinearAlgebra.BlasInt}
      return Main.arpack_dgetv0!(ido, BMAT, itry, initv, n, j, V, ldv, resid, rnorm, ipntr, workd)
    elseif state.handle_getv0 == :check 
      # make a copy of everything before sending it to Arpack...
      arido = Ref{Int}(ido[])
      arv = copy(V)
      arresid = copy(resid) 
      arrnorm = Ref{T}(rnorm[])
      aripntr = copy(ipntr)
      arworkd = copy(workd) 

      ierr = ArpackInJulia.dgetv0!(
        ido, Val(BMAT), itry, initv, n, j, V, ldv, resid, rnorm, ipntr, workd,
        normalstate; stats, debug, idonow)
      
      arierr = Main.arpack_dgetv0!(
        arido, BMAT, itry, initv, n, j, arv, ldv, arresid, arrnorm, aripntr, arworkd)
  
      @test arierr == ierr
      @test arido[] == ido[]
      @test arv == V
      @test arresid == resid
      @test arrnorm[] == rnorm[]
      @test aripntr == ipntr
      @test arworkd == workd        

      state.getv0 = normalstate.getv0
      return ierr
    else
      @error("Shouldn't get here. state.handle_getv0 = $(state.handle_getv0) is not ':use' or ':check'")
    end  
  end 
end

function _run_saitr_sequence!(M; 
  B=1.0LinearAlgebra.I,
  idostart::Int,
  bmat::Symbol,
  n::Int,
  k::Int, 
  np::Int,
  mode::Int,
  resid::AbstractVecOrMat{T},
  rnorm::Ref{T},
  V::AbstractMatrix{T},
  ldv::Int,
  H::AbstractMatrix{T},
  ldh::Int,
  stats = nothing,
  debug = nothing, 
  state = nothing, 
  idonow = nothing, 
) where T
  resid0 = copy(resid)

  @assert(size(M,1) == n)

  ido = Ref{Int}(idostart)
  ipntr = zeros(Int, 3)
  workd = zeros(3n)

  histdata = Vector{
      NamedTuple{(:info,:ido,:rnorm), Tuple{Int64,Int64,T}}
  }()

  if state === nothing
    state = ArpackInJulia.ArpackState{Float64}()
  end 
  while ido[] != 99
    info = ArpackInJulia.dsaitr!(
      ido, Val(bmat), n, k, np, mode, resid, rnorm, V, ldv, H, ldh, ipntr, workd, state; 
      stats, debug, idonow)

    if ido[] == -1 || ido[] == 1
      if mode == 2
        # crazy interface, see remark 5 
        mul!(@view(workd[ipntr[2]:ipntr[2]+n-1]),M,@view(workd[ipntr[1]:ipntr[1]+n-1]))
        copyto!(@view(workd[ipntr[1]:ipntr[1]+n-1]),@view(workd[ipntr[2]:ipntr[2]+n-1]))
        ldiv!(@view(workd[ipntr[2]:ipntr[2]+n-1]),B,@view(workd[ipntr[1]:ipntr[1]+n-1]))
      else
        mul!(@view(workd[ipntr[2]:ipntr[2]+n-1]),M,@view(workd[ipntr[1]:ipntr[1]+n-1]))
      end 
    elseif ido[] == 2
      mul!(@view(workd[ipntr[2]:ipntr[2]+n-1]),B,@view(workd[ipntr[1]:ipntr[1]+n-1]))
    elseif ido[] == 99 
      # we are done... will exit...
    else
      @error("Wrong ido, $(ido[])")
    end

    push!(histdata, (;info,ido=ido[],rnorm=rnorm[]))
  end
  return histdata
end

@testset "Check internal calls" begin 
  @testset "getv0 use Arpackjll" begin 
    using LinearAlgebra
    using Random 
    Random.seed!(0)
    ido = Ref{Int}(0)
    bmat = :I
    n = 10
    k = 0 # number of current columns in V
    np = 1
    mode = 1
    resid = collect(1.0:n)
    rnorm = Ref{Float64}(norm(resid))
    V = zeros(n,k+np+1)
    ldv = n 
    H = zeros(n,2) # full h
    ldh = n 
    M = Diagonal(1.0I, 10) # 10x10 identity 


    _reset_libarpack_dgetv0_iseed()

    state = CheckWithArpackjll.ArpackjllState{Float64}()
    state.handle_getv0 = :use
    stats = ArpackStats()
    @test_nowarn rval = _run_saitr_sequence!(M; idostart=0,
      n, k, np, mode, resid, rnorm, V, H, ldv, ldh, bmat, stats, state
    )
    @test stats.nrstrt == 0 
    # resid should be zero... 
    @test norm(resid) ≈ 0 atol=n*eps(1.0)

    k = 0 # number of current columns in V
    np = 2
    resid = collect(1.0:n)
    rnorm = Ref{Float64}(norm(resid))
    @test_nowarn rval = _run_saitr_sequence!(M; idostart=0,
      n, k, np, mode, resid, rnorm, V, H, ldv, ldh, bmat, stats, state
    )
    @test stats.nrstrt > 0 
    @test stats.tgetv0 == 0 
    # because it's the identity, resid should still be zero...
    @test norm(resid) ≈ 0 atol=n*eps(1.0)
  end 

  @testset "getv0 check Arpackjll" begin 
    using LinearAlgebra
    using Random 
    Random.seed!(0)
    ido = Ref{Int}(0)
    bmat = :I
    n = 10
    k = 0 # number of current columns in V
    np = 1
    mode = 1
    resid = collect(1.0:n)
    rnorm = Ref{Float64}(norm(resid))
    V = zeros(n,k+np+1)
    ldv = n 
    H = zeros(n,2) # full h
    ldh = n 
    M = Diagonal(1.0I, 10) # 10x10 identity 


    _reset_libarpack_dgetv0_iseed()

    state = CheckWithArpackjll.ArpackjllState{Float64}()
    state.handle_getv0 = :check
    stats = ArpackStats()
    @test_nowarn rval = _run_saitr_sequence!(M; idostart=0,
      n, k, np, mode, resid, rnorm, V, H, ldv, ldh, bmat, stats, state
    )
    @test stats.nrstrt == 0 
    # resid should be zero... 
    @test norm(resid) ≈ 0 atol=n*eps(1.0)

    k = 0 # number of current columns in V
    np = 2
    resid = collect(1.0:n)
    rnorm = Ref{Float64}(norm(resid))
    @test_nowarn rval = _run_saitr_sequence!(M; idostart=0,
      n, k, np, mode, resid, rnorm, V, H, ldv, ldh, bmat, stats, state
    )
    @test stats.nrstrt > 0 
    @test stats.tgetv0 > 0 
    # because it's the identity, resid should still be zero...
    @test norm(resid) ≈ 0 atol=n*eps(1.0)
  end 
end 