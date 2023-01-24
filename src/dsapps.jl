#=
c-----------------------------------------------------------------------
c\BeginDoc
c
c\Name: dsapps
c
c\Description:
c  Given the Arnoldi factorization
c
c     A*V_{k} - V_{k}*H_{k} = r_{k+p}*e_{k+p}^T,
c
c  apply NP shifts implicitly resulting in
c
c     A*(V_{k}*Q) - (V_{k}*Q)*(Q^T* H_{k}*Q) = r_{k+p}*e_{k+p}^T * Q
c
c  where Q is an orthogonal matrix of order KEV+NP. Q is the product of 
c  rotations resulting from the NP bulge chasing sweeps.  The updated Arnoldi 
c  factorization becomes:
c
c     A*VNEW_{k} - VNEW_{k}*HNEW_{k} = rnew_{k}*e_{k}^T.
c
c\Usage:
c  call dsapps
c     ( N, KEV, NP, SHIFT, V, LDV, H, LDH, RESID, Q, LDQ, WORKD )
c
c\Arguments
c  N       Integer.  (INPUT)
c          Problem size, i.e. dimension of matrix A.
c
c  KEV     Integer.  (INPUT)
c          INPUT: KEV+NP is the size of the input matrix H.
c          OUTPUT: KEV is the size of the updated matrix HNEW.
c
c  NP      Integer.  (INPUT)
c          Number of implicit shifts to be applied.
c
c  SHIFT   Double precision array of length NP.  (INPUT)
c          The shifts to be applied.
c
c  V       Double precision N by (KEV+NP) array.  (INPUT/OUTPUT)
c          INPUT: V contains the current KEV+NP Arnoldi vectors.
c          OUTPUT: VNEW = V(1:n,1:KEV); the updated Arnoldi vectors
c          are in the first KEV columns of V.
c
c  LDV     Integer.  (INPUT)
c          Leading dimension of V exactly as declared in the calling
c          program.
c
c  H       Double precision (KEV+NP) by 2 array.  (INPUT/OUTPUT)
c          INPUT: H contains the symmetric tridiagonal matrix of the
c          Arnoldi factorization with the subdiagonal in the 1st column
c          starting at H(2,1) and the main diagonal in the 2nd column.
c          OUTPUT: H contains the updated tridiagonal matrix in the 
c          KEV leading submatrix.
c
c  LDH     Integer.  (INPUT)
c          Leading dimension of H exactly as declared in the calling
c          program.
c
c  RESID   Double precision array of length (N).  (INPUT/OUTPUT)
c          INPUT: RESID contains the the residual vector r_{k+p}.
c          OUTPUT: RESID is the updated residual vector rnew_{k}.
c
c  Q       Double precision KEV+NP by KEV+NP work array.  (WORKSPACE)
c          Work array used to accumulate the rotations during the bulge
c          chase sweep.
c
c  LDQ     Integer.  (INPUT)
c          Leading dimension of Q exactly as declared in the calling
c          program.
c
c  WORKD   Double precision work array of length 2*N.  (WORKSPACE)
c          Distributed array used in the application of the accumulated
c          orthogonal matrix Q.
c
c\EndDoc
c
c-----------------------------------------------------------------------
c
c\BeginLib
c
c\Local variables:
c     xxxxxx  real
c
c\References:
c  1. D.C. Sorensen, "Implicit Application of Polynomial Filters in
c     a k-Step Arnoldi Method", SIAM J. Matr. Anal. Apps., 13 (1992),
c     pp 357-385.
c  2. R.B. Lehoucq, "Analysis and Implementation of an Implicitly 
c     Restarted Arnoldi Iteration", Rice University Technical Report
c     TR95-13, Department of Computational and Applied Mathematics.
c
c\Routines called:
c     ivout   ARPACK utility routine that prints integers. 
c     arscnd  ARPACK utility routine for timing.
c     dvout   ARPACK utility routine that prints vectors.
c     dlamch  LAPACK routine that determines machine constants.
c     dlartg  LAPACK Givens rotation construction routine.
c     dlacpy  LAPACK matrix copy routine.
c     dlaset  LAPACK matrix initialization routine.
c     dgemv   Level 2 BLAS routine for matrix vector multiplication.
c     daxpy   Level 1 BLAS that computes a vector triad.
c     dcopy   Level 1 BLAS that copies one vector to another.
c     dscal   Level 1 BLAS that scales a vector.
c
c\Author
c     Danny Sorensen               Phuong Vu
c     Richard Lehoucq              CRPC / Rice University
c     Dept. of Computational &     Houston, Texas
c     Applied Mathematics
c     Rice University           
c     Houston, Texas            
c
c\Revision history:
c     12/16/93: Version ' 2.4'
c
c\SCCS Information: @(#) 
c FILE: sapps.F   SID: 2.6   DATE OF SID: 3/28/97   RELEASE: 2
c
c\Remarks
c  1. In this version, each shift is applied to all the subblocks of
c     the tridiagonal matrix H and not just to the submatrix that it 
c     comes from. This routine assumes that the subdiagonal elements 
c     of H that are stored in h(1:kev+np,1) are nonegative upon input
c     and enforce this condition upon output. This version incorporates
c     deflation. See code for documentation.
c
c\EndLib
c
c-----------------------------------------------------------------------
c
      subroutine dsapps
     &   ( n, kev, np, shift, v, ldv, h, ldh, resid, q, ldq, workd )
c
c     %----------------------------------------------------%
c     | Include files for debugging and timing information |
c     %----------------------------------------------------%
c
      include   'debug.h'
      include   'stat.h'
c
c     %------------------%
c     | Scalar Arguments |
c     %------------------%
c
      integer    kev, ldh, ldq, ldv, n, np
c
c     %-----------------%
c     | Array Arguments |
c     %-----------------%
c
      Double precision
     &           h(ldh,2), q(ldq,kev+np), resid(n), shift(np), 
     &           v(ldv,kev+np), workd(2*n)
c
c     %------------%
c     | Parameters |
c     %------------%
c
      Double precision
     &           one, zero
      parameter (one = 1.0D+0, zero = 0.0D+0)
c
c     %---------------%
c     | Local Scalars |
c     %---------------%
c
      integer    i, iend, istart, itop, j, jj, kplusp, msglvl
      logical    first
      Double precision
     &           a1, a2, a3, a4, big, c, epsmch, f, g, r, s
      save       epsmch, first
c
c
c     %----------------------%
c     | External Subroutines |
c     %----------------------%
c
      external   daxpy, dcopy, dscal, dlacpy, dlartg, dlaset, dvout, 
     &           ivout, arscnd, dgemv
c
c     %--------------------%
c     | External Functions |
c     %--------------------%
c
      Double precision
     &           dlamch
      external   dlamch
c
c     %----------------------%
c     | Intrinsics Functions |
c     %----------------------%
c
      intrinsic  abs
c
c     %----------------%
c     | Data statments |
c     %----------------%
c
      data       first / .true. /
c
c     %-----------------------%
c     | Executable Statements |
c     %-----------------------%
c
      if (first) then
         epsmch = dlamch('Epsilon-Machine')
         first = .false.
      end if
      itop = 1
c
c     %-------------------------------%
c     | Initialize timing statistics  |
c     | & message level for debugging |
c     %-------------------------------%
c
      call arscnd (t0)
      msglvl = msapps
c 
      kplusp = kev + np 
c 
c     %----------------------------------------------%
c     | Initialize Q to the identity matrix of order |
c     | kplusp used to accumulate the rotations.     |
c     %----------------------------------------------%
c
      call dlaset ('All', kplusp, kplusp, zero, one, q, ldq)
c
c     %----------------------------------------------%
c     | Quick return if there are no shifts to apply |
c     %----------------------------------------------%
c
      if (np .eq. 0) go to 9000
c 
c     %----------------------------------------------------------%
c     | Apply the np shifts implicitly. Apply each shift to the  |
c     | whole matrix and not just to the submatrix from which it |
c     | comes.                                                   |
c     %----------------------------------------------------------%
c
      do 90 jj = 1, np
c 
         istart = itop
c
c        %----------------------------------------------------------%
c        | Check for splitting and deflation. Currently we consider |
c        | an off-diagonal element h(i+1,1) negligible if           |
c        |         h(i+1,1) .le. epsmch*( |h(i,2)| + |h(i+1,2)| )   |
c        | for i=1:KEV+NP-1.                                        |
c        | If above condition tests true then we set h(i+1,1) = 0.  |
c        | Note that h(1:KEV+NP,1) are assumed to be non negative.  |
c        %----------------------------------------------------------%
c
   20    continue
c
c        %------------------------------------------------%
c        | The following loop exits early if we encounter |
c        | a negligible off diagonal element.             |
c        %------------------------------------------------%
c
         do 30 i = istart, kplusp-1
            big   = abs(h(i,2)) + abs(h(i+1,2))
            if (h(i+1,1) .le. epsmch*big) then
               if (msglvl .gt. 0) then
                  call ivout (logfil, 1, i, ndigit, 
     &                 '_sapps: deflation at row/column no.')
                  call ivout (logfil, 1, jj, ndigit, 
     &                 '_sapps: occurred before shift number.')
                  call dvout (logfil, 1, h(i+1,1), ndigit, 
     &                 '_sapps: the corresponding off diagonal element')
               end if
               h(i+1,1) = zero
               iend = i
               go to 40
            end if
   30    continue
         iend = kplusp
   40    continue
c
         if (istart .lt. iend) then
c 
c           %--------------------------------------------------------%
c           | Construct the plane rotation G'(istart,istart+1,theta) |
c           | that attempts to drive h(istart+1,1) to zero.          |
c           %--------------------------------------------------------%
c
             f = h(istart,2) - shift(jj)
             g = h(istart+1,1)
             call dlartg (f, g, c, s, r)
c 
c            %-------------------------------------------------------%
c            | Apply rotation to the left and right of H;            |
c            | H <- G' * H * G,  where G = G(istart,istart+1,theta). |
c            | This will create a "bulge".                           |
c            %-------------------------------------------------------%
c
             a1 = c*h(istart,2)   + s*h(istart+1,1)
             a2 = c*h(istart+1,1) + s*h(istart+1,2)
             a4 = c*h(istart+1,2) - s*h(istart+1,1)
             a3 = c*h(istart+1,1) - s*h(istart,2) 
             h(istart,2)   = c*a1 + s*a2
             h(istart+1,2) = c*a4 - s*a3
             h(istart+1,1) = c*a3 + s*a4
c 
c            %----------------------------------------------------%
c            | Accumulate the rotation in the matrix Q;  Q <- Q*G |
c            %----------------------------------------------------%
c
             do 60 j = 1, min(istart+jj,kplusp)
                a1            =   c*q(j,istart) + s*q(j,istart+1)
                q(j,istart+1) = - s*q(j,istart) + c*q(j,istart+1)
                q(j,istart)   = a1
   60        continue
c
c
c            %----------------------------------------------%
c            | The following loop chases the bulge created. |
c            | Note that the previous rotation may also be  |
c            | done within the following loop. But it is    |
c            | kept separate to make the distinction among  |
c            | the bulge chasing sweeps and the first plane |
c            | rotation designed to drive h(istart+1,1) to  |
c            | zero.                                        |
c            %----------------------------------------------%
c
             do 70 i = istart+1, iend-1
c 
c               %----------------------------------------------%
c               | Construct the plane rotation G'(i,i+1,theta) |
c               | that zeros the i-th bulge that was created   |
c               | by G(i-1,i,theta). g represents the bulge.   |
c               %----------------------------------------------%
c
                f = h(i,1)
                g = s*h(i+1,1)
c
c               %----------------------------------%
c               | Final update with G(i-1,i,theta) |
c               %----------------------------------%
c
                h(i+1,1) = c*h(i+1,1)
                call dlartg (f, g, c, s, r)
c
c               %-------------------------------------------%
c               | The following ensures that h(1:iend-1,1), |
c               | the first iend-2 off diagonal of elements |
c               | H, remain non negative.                   |
c               %-------------------------------------------%
c
                if (r .lt. zero) then
                   r = -r
                   c = -c
                   s = -s
                end if
c 
c               %--------------------------------------------%
c               | Apply rotation to the left and right of H; |
c               | H <- G * H * G',  where G = G(i,i+1,theta) |
c               %--------------------------------------------%
c
                h(i,1) = r
c 
                a1 = c*h(i,2)   + s*h(i+1,1)
                a2 = c*h(i+1,1) + s*h(i+1,2)
                a3 = c*h(i+1,1) - s*h(i,2)
                a4 = c*h(i+1,2) - s*h(i+1,1)
c 
                h(i,2)   = c*a1 + s*a2
                h(i+1,2) = c*a4 - s*a3
                h(i+1,1) = c*a3 + s*a4
c 
c               %----------------------------------------------------%
c               | Accumulate the rotation in the matrix Q;  Q <- Q*G |
c               %----------------------------------------------------%
c
                do 50 j = 1, min( i+jj, kplusp )
                   a1       =   c*q(j,i) + s*q(j,i+1)
                   q(j,i+1) = - s*q(j,i) + c*q(j,i+1)
                   q(j,i)   = a1
   50           continue
c
   70        continue
c
         end if
c
c        %--------------------------%
c        | Update the block pointer |
c        %--------------------------%
c
         istart = iend + 1
c
c        %------------------------------------------%
c        | Make sure that h(iend,1) is non-negative |
c        | If not then set h(iend,1) <-- -h(iend,1) |
c        | and negate the last column of Q.         |
c        | We have effectively carried out a        |
c        | similarity on transformation H           |
c        %------------------------------------------%
c
         if (h(iend,1) .lt. zero) then
             h(iend,1) = -h(iend,1)
             call dscal(kplusp, -one, q(1,iend), 1)
         end if
c
c        %--------------------------------------------------------%
c        | Apply the same shift to the next block if there is any |
c        %--------------------------------------------------------%
c
         if (iend .lt. kplusp) go to 20
c
c        %-----------------------------------------------------%
c        | Check if we can increase the the start of the block |
c        %-----------------------------------------------------%
c
         do 80 i = itop, kplusp-1
            if (h(i+1,1) .gt. zero) go to 90
            itop  = itop + 1
   80    continue
c
c        %-----------------------------------%
c        | Finished applying the jj-th shift |
c        %-----------------------------------%
c
   90 continue
c
c     %------------------------------------------%
c     | All shifts have been applied. Check for  |
c     | more possible deflation that might occur |
c     | after the last shift is applied.         |                               
c     %------------------------------------------%
c
      do 100 i = itop, kplusp-1
         big   = abs(h(i,2)) + abs(h(i+1,2))
         if (h(i+1,1) .le. epsmch*big) then
            if (msglvl .gt. 0) then
               call ivout (logfil, 1, i, ndigit, 
     &              '_sapps: deflation at row/column no.')
               call dvout (logfil, 1, h(i+1,1), ndigit, 
     &              '_sapps: the corresponding off diagonal element')
            end if
            h(i+1,1) = zero
         end if
 100  continue
c
c     %-------------------------------------------------%
c     | Compute the (kev+1)-st column of (V*Q) and      |
c     | temporarily store the result in WORKD(N+1:2*N). |
c     | This is not necessary if h(kev+1,1) = 0.         |
c     %-------------------------------------------------%
c
      if ( h(kev+1,1) .gt. zero ) 
     &   call dgemv ('N', n, kplusp, one, v, ldv,
     &                q(1,kev+1), 1, zero, workd(n+1), 1)
c 
c     %-------------------------------------------------------%
c     | Compute column 1 to kev of (V*Q) in backward order    |
c     | taking advantage that Q is an upper triangular matrix |    
c     | with lower bandwidth np.                              |
c     | Place results in v(:,kplusp-kev:kplusp) temporarily.  |
c     %-------------------------------------------------------%
c
      do 130 i = 1, kev
         call dgemv ('N', n, kplusp-i+1, one, v, ldv,
     &               q(1,kev-i+1), 1, zero, workd, 1)
         call dcopy (n, workd, 1, v(1,kplusp-i+1), 1)
  130 continue
c
c     %-------------------------------------------------%
c     |  Move v(:,kplusp-kev+1:kplusp) into v(:,1:kev). |
c     %-------------------------------------------------%
c
      do 140 i = 1, kev
         call dcopy (n, v(1,np+i), 1, v(1,i), 1)
  140 continue
c 
c     %--------------------------------------------%
c     | Copy the (kev+1)-st column of (V*Q) in the |
c     | appropriate place if h(kev+1,1) .ne. zero. |
c     %--------------------------------------------%
c
      if ( h(kev+1,1) .gt. zero ) 
     &     call dcopy (n, workd(n+1), 1, v(1,kev+1), 1)
c 
c     %-------------------------------------%
c     | Update the residual vector:         |
c     |    r <- sigmak*r + betak*v(:,kev+1) |
c     | where                               |
c     |    sigmak = (e_{kev+p}'*Q)*e_{kev}  |
c     |    betak = e_{kev+1}'*H*e_{kev}     |
c     %-------------------------------------%
c
      call dscal (n, q(kplusp,kev), resid, 1)
      if (h(kev+1,1) .gt. zero) 
     &   call daxpy (n, h(kev+1,1), v(1,kev+1), 1, resid, 1)
c
      if (msglvl .gt. 1) then
         call dvout (logfil, 1, q(kplusp,kev), ndigit, 
     &      '_sapps: sigmak of the updated residual vector')
         call dvout (logfil, 1, h(kev+1,1), ndigit, 
     &      '_sapps: betak of the updated residual vector')
         call dvout (logfil, kev, h(1,2), ndigit, 
     &      '_sapps: updated main diagonal of H for next iteration')
         if (kev .gt. 1) then
         call dvout (logfil, kev-1, h(2,1), ndigit, 
     &      '_sapps: updated sub diagonal of H for next iteration')
         end if
      end if
c
      call arscnd (t1)
      tsapps = tsapps + (t1 - t0)
c 
 9000 continue 
      return
c
c     %---------------%
c     | End of dsapps |
c     %---------------%
c
      end
=#      

"""
Usage:
call dsapps
   ( N, KEV, NP, SHIFT, V, LDV, H, LDH, RESID, Q, LDQ, WORKD )

Arguments
N       Integer.  (INPUT)
        Problem size, i.e. dimension of matrix A.

KEV     Integer.  (INPUT)
        INPUT: KEV+NP is the size of the input matrix H.
        OUTPUT: KEV is the size of the updated matrix HNEW.

NP      Integer.  (INPUT)
        Number of implicit shifts to be applied.

SHIFT   Double precision array of length NP.  (INPUT)
        The shifts to be applied.

V       Double precision N by (KEV+NP) array.  (INPUT/OUTPUT)
        INPUT: V contains the current KEV+NP Arnoldi vectors.
        OUTPUT: VNEW = V(1:n,1:KEV); the updated Arnoldi vectors
        are in the first KEV columns of V.

LDV     Integer.  (INPUT)
        Leading dimension of V exactly as declared in the calling
        program.

H       Double precision (KEV+NP) by 2 array.  (INPUT/OUTPUT)
        INPUT: H contains the symmetritridiagonal matrix of the
        Arnoldi factorization with the subdiagonal in the 1st column
        starting at H(2,1) and the main diagonal in the 2nd column.
        OUTPUT: H contains the updated tridiagonal matrix in the 
        KEV leading submatrix.

LDH     Integer.  (INPUT)
        Leading dimension of H exactly as declared in the calling
        program.

RESID   Double precision array of length (N).  (INPUT/OUTPUT)
        INPUT: RESID contains the the residual vector r_{k+p}.
        OUTPUT: RESID is the updated residual vector rnew_{k}.

Q       Double precision KEV+NP by KEV+NP work array.  (WORKSPACE)
        Work array used to accumulate the rotations during the bulge
        chase sweep.

LDQ     Integer.  (INPUT)
        Leading dimension of Q exactly as declared in the calling
        program.

WORKD   Double precision work array of length 2*N.  (WORKSPACE)
        Distributed array used in the application of the accumulated
        orthogonal matrix Q.
"""
function dsapps!(
  n::Int,
  kev::Int,
  np::Int,
  shift::AbstractVecOrMat{TR},
  V::AbstractMatrix{T},
  ldv::Int,
  H::AbstractMatrix{TR},
  ldh::Int,
  resid::AbstractVecOrMat{T},
  Q::AbstractMatrix{TR},
  ldq::Int,
  workd::AbstractVecOrMat{T},
  state::Union{AbstractArpackState{TR},Nothing}
  ;
  stats::Union{ArpackStats,Nothing}=nothing,
  debug::Union{ArpackDebug,Nothing}=nothing,
) where {T,TR}

  @jl_arpack_check_size(V, n, kev+np) # needs to be this long
  @jl_arpack_check_size(H, kev+np, 2)
  # make sure our leading dimensions are correct 
  # these mean we need ldv entries in each column until the last... where we need fewer
  @jl_arpack_check_length(V, ldv*(kev+np-1)+(kev+np)) 
  @jl_arpack_check_length(H, ldh+kev+np)

  @jl_arpack_check_length(resid, n)
  @jl_arpack_check_length(workd, 2n)
  @jl_arpack_check_length(shift, np)
  @jl_arpack_check_size(Q, kev+np, kev+np) # needs to be this size 
  @jl_arpack_check_length(Q, ldq*(kev+np-1) + (kev+np)) # should be this long...

  epsmch = eps(TR)/2
  itop = 1

  # c     | Initialize timing statistics  |
  # c     | & message level for debugging |
  t0 = @jl_arpack_time()
  msglvl = @jl_arpack_debug(mapps,0)

  kplusp = kev+np

  # c     | Initialize Q to the identity matrix of order |
  # c     | kplusp used to accumulate the rotations.     |
  # this should not do any allocation and treat one(T)*I implicitly
  # based on testing on 2022-03-04
  copyto!(@view(Q[1:kplusp, 1:kplusp]), one(T)*LinearAlgebra.I)

  # c     | Quick return if there are no shifts to apply |
  # if (np == 0) return
  # removed for Julia because it just complicates the code
  # the for loop below will do the same thing.
  
  #= 
  c     | Apply the np shifts implicitly. Apply each shift to the  |
  c     | whole matrix and not just to the submatrix from which it |
  c     | comes.                                                   |
  =#
  for jj=1:np
    istart = itop

    #=
    c        | Check for splitting and deflation. Currently we consider |
    c        | an off-diagonal element h(i+1,1) negligible if           |
    c        |         h(i+1,1) .le. epsmch*( |h(i,2)| + |h(i+1,2)| )   |
    c        | for i=1:KEV+NP-1.                                        |
    c        | If above condition tests true then we set h(i+1,1) = 0.  |
    c        | Note that h(1:KEV+NP,1) are assumed to be non negative.  |
    =#
    # in Fortran, there is a label 20 here to setup a loop to keep iterating
    # over blocks that have been split. 
    # so the alg is: find a block; apply shifts; find next block... 
    # the loop in Fortran is 
    #   istart -> find iend; loop body; istart = iend + 1; if iend < kplusp, go back to start. 
    # which we map to 
    # while istart <= kplusp
    #   find iend; loop body; istart = iend + 1; 
    # end which will end in the same place.
    while istart <= kplusp 
      # we will apply shift jj 

      # c        | The following loop exits early if we encounter |
      # c        | a negligible off diagonal element.             |
      iend = kplusp # this may be reduced by the Julia loop 
      for i=istart:kplusp-1
        big = abs(H[i,2]) + abs(H[i+1,2])
        if (H[i+1,1] <= epsmch*big) 
          if msglvl > 0
            println(debug.logfile, "_sapps: deflation at row/column no. ", i)
            println(debug.logfile, "_sapps: occurred before shift number. ", jj)
            println(debug.logfile, "_sapps: the corresponding off diagonal element ", H[i+1,1])
          end
          H[i+1,1] = 0
          iend=i
          break # go to 40, but we already set iend to the default above, so just exit the loop
        end
      end
      # In Julia, we set iend = kplusp at initialization, but then may reduce it in the loop



      if istart < iend
        # c           | Construct the plane rotation G'(istart,istart+1,theta) |
        # c           | that attempts to drive h(istart+1,1) to zero.          |
        f = H[istart,2] - shift[jj]
        g = H[istart+1,1]
        c, s, r = plane_rotation(f, g)
        #=
        c            | Apply rotation to the left and right of H;            |
        c            | H <- G' * H * G,  where G = G(istart,istart+1,theta). |
        c            | This will create a "bulge".                           |
        =#  
        a1 = c*H[istart,2]   + s*H[istart+1,1]
        a2 = c*H[istart+1,1] + s*H[istart+1,2]
        a4 = c*H[istart+1,2] - s*H[istart+1,1]
        a3 = c*H[istart+1,1] - s*H[istart,2]
        H[istart,2]   = c*a1 + s*a2
        H[istart+1,2] = c*a4 - s*a3
        H[istart+1,1] = c*a3 + s*a4

        # c            | Accumulate the rotation in the matrix Q;  Q <- Q*G |
        for j=1:min(istart+jj,kplusp)
          a1 = c*Q[j,istart] + s*Q[j,istart+1]
          Q[j,istart+1]  = -s*Q[j,istart] + c*Q[j,istart+1]
          Q[j,istart] = a1
        end

        #=
        c            | The following loop chases the bulge created. |
        c            | Note that the previous rotation may also be  |
        c            | done within the following loop. But it is    |
        c            | kept separate to make the distinction among  |
        c            | the bulge chasing sweeps and the first plane |
        c            | rotation designed to drive h(istart+1,1) to  |
        c            | zero.                                        |
        =#
        for i=istart+1:iend-1
          #=
          c               | Construct the plane rotation G'(i,i+1,theta) |
          c               | that zeros the i-th bulge that was created   |
          c               | by G(i-1,i,theta). g represents the bulge.   |
          =#
          f = H[i,1]
          g = s*H[i+1,1]

          # c               | Final update with G(i-1,i,theta) |
          H[i+1,1] = c*H[i+1,1]
          c, s, r = plane_rotation(f, g)

          #=
          c               | The following ensures that h(1:iend-1,1), |
          c               | the first iend-2 off diagonal of elements |
          c               | H, remain non negative.                   |
          =#

          if r < 0
            r = -r
            c = -c
            s = -s
          end

          # c               | Apply rotation to the left and right of H; |
          # c               | H <- G * H * G',  where G = G(i,i+1,theta) |
          H[i,1] = r

          a1 = c*H[i,2]   + s*H[i+1,1]
          a2 = c*H[i+1,1] + s*H[i+1,2]
          a3 = c*H[i+1,1] - s*H[i,2]
          a4 = c*H[i+1,2] - s*H[i+1,1]
          H[i,2]   = c*a1 + s*a2
          H[i+1,2] = c*a4 - s*a3
          H[i+1,1] = c*a3 + s*a4

          # c               | Accumulate the rotation in the matrix Q;  Q <- Q*G |
          for j=1:min(i+jj,kplusp)
            a1 = c*Q[j,i] + s*Q[j,i+1]
            Q[j,i+1] = -s*Q[j,i] + c*Q[j,i+1]
            Q[j,i] = a1 
          end
        end
      end

      #=
      c        | Make sure that h(iend,1) is non-negative |
      c        | If not then set h(iend,1) <-- -h(iend,1) |
      c        | and negate the last column of Q.         |
      c        | We have effectively carried out a        |
      c        | similarity on transformation H           |
      =#
      if (H[iend,1] < 0)
        H[iend,1] *= -1
        _dscal!(-one(T), @view(Q[1:kplusp,iend]))
      end

      # c        | Update the block pointer |
      istart = iend+1

      # c        | Apply the same shift to the next block if there is any |
      # this is checked by the istart <= kplusp 
      # if (iend .lt. kplusp) go to 20
      # istart = iend + 1 <= kplusp to continue the loop 
    end 

    # c        | Check if we can increase the the start of the block |
    for i=itop:kplusp-1
      if H[i+1,1] > 0
        break # stop this loop and go to the next iteration with jj
      else
        itop += 1 
      end 
    end
    # c        | Finished applying the jj-th shift |
  end 

  #=
  c     | All shifts have been applied. Check for  |
  c     | more possible deflation that might occur |
  c     | after the last shift is applied.         |     
  =#
  for i=itop:kplusp-1
    big = abs(H[i,2]) + abs(H[i+1,2])
    if (H[i+1,1] <= epsmch*big) 
      if msglvl > 0
        println(debug.logfile, "_sapps: deflation at row/column no. ", i)
        println(debug.logfile, "_sapps: the corresponding off diagonal element ", H[i+1,1])
      end
      H[i+1,1] = 0
    end
  end

  # Oh, the rare comment mis-alignment in Arpack code !
  #=
  c     | Compute the (kev+1)-st column of (V*Q) and      |
  c     | temporarily store the result in WORKD(N+1:2*N). |
  c     | This is not necessary if h(kev+1,1) = 0.         |
  =#
  if (H[kev+1,1] > 0)
    #   mul!(C, A, B, α, β) -> C = ABα + Cβ
    mul!(@view(workd[n+1:2n]), @view(V[1:n,1:kplusp]), @view(Q[1:kplusp,kev+1]),
      one(T), zero(T))
  end

  #=
  c     | Compute column 1 to kev of (V*Q) in backward order    |
  c     | taking advantage that Q is an upper triangular matrix |    
  c     | with lower bandwidth np.                              |
  c     | Place results in v(:,kplusp-kev:kplusp) temporarily.  |
  =#
  for i=1:kev
    band = kplusp-i+1
    mul!(@view(workd[1:n]), @view(V[1:n, 1:band]), @view(Q[1:band,kev-i+1]),
      one(T), zero(T))
    copyto!(@view(V[1:n,band]), @view(workd[1:n]))
  end

  # c     |  Move v(:,kplusp-kev+1:kplusp) into v(:,1:kev). |
  for i=1:kev
    copyto!(@view(V[1:n,i]), @view(V[1:n,np+i]))
  end

  # c     | Copy the (kev+1)-st column of (V*Q) in the |
  # c     | appropriate place if h(kev+1,1) .ne. zero. |
  if (H[kev+1,1] > 0)
    copyto!(@view(V[1:n, kev+1]), @view(workd[n+1:2n]))
  end

  #=
  c     | Update the residual vector:         |
  c     |    r <- sigmak*r + betak*v(:,kev+1) |
  c     | where                               |
  c     |    sigmak = (e_{kev+p}'*Q)*e_{kev}  |
  c     |    betak = e_{kev+1}'*H*e_{kev}     |
  =#
  _dscal!(Q[kplusp,kev], @view(resid[1:n]))
  if H[kev+1,1] > 0
    # axpy!(a, X, Y), Overwrite Y with X*a + Y,
    LinearAlgebra.axpy!(H[kev+1,1], @view(V[1:n,kev+1]), @view(resid[1:n]))
  end 

  if msglvl > 0 
    println(debug.logfile, "_sapps: sigmak of the updated residual vector ", Q[kplusp,kev])
    println(debug.logfile, "_sapps: betak of the updated residual vector ", H[kev+1,1])
    _arpack_vout(debug, "_sapps: updated main diagonal of H for next iteration", 
      @view(H[1:kev,2]))
    if kev > 1
      _arpack_vout(debug, "_sapps: updated sub diagonal of H for next iteration", 
        @view(H[2:kev,1]))
    end 
  end

  @jl_update_time(tapps, t0)
  return nothing
end 
