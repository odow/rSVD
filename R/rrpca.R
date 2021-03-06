#' @title  Randomized robust principal component analysis (rrpca).
#
#' @description Robust principal components analysis using randomized singular value decomposition.
#
#' @details
#' Robust principal component analysis (RPCA) is a method for the robust seperation of a
#' a rectangular \eqn{(m,n)} matrix \eqn{A} into a low-rank component \eqn{L} and a
#' sparse comonent \eqn{S} as follows: \eqn{A=L+S}.
#' Here we are using the fast randomized accelerated inexact augmented Lagrange multiplier
#' method (IALM) for obtaining the robust seperation.
#'
#'
#' @param A       array_like \cr
#'                a numeric input matrix (or data frame), with dimensions \eqn{(m, n)}. \cr
#'                If the data contain \eqn{NA}s na.omit is applied.
#'
#' @param k       int, optional \cr
#'                determines the number of principle components to compute. It is required that \eqn{k} is smaller or equal to
#'                \eqn{n}, but it is recommended that \eqn{k << min(m,n)}.
#'
#' @param lamb    real, optional \cr
#'                tuning paramter (default \eqn{lamb=max(m,n)^-0.5}).
#'
#' @param gamma   real, optional \cr
#'                tuning paramter (default \eqn{gamma=1.25}).
#'
#' @param rho     real, optional \cr
#'                tuning paramter (default \eqn{rho=1.5}).
#'
#' @param maxiter int, optional \cr
#'                determines the maximal numbers of iterations (default \eqn{maxiter=20})..
#'
#' @param tol     real, optional \cr
#'                tolarance paramter for the desired convergence of the algorithm.
#'
#' @param svdalg  str c('auto', 'rsvd', 'svd'), optional \cr
#'                Determines which algorithm should be used for computing the singular value decomposition.
#'                By default 'auto' is used, which decides whether to use \code{\link{rsvd}} or \code{\link{svd}},
#'                depending on the number of principle components. If \eqn{k < min(n,m)/1.5} randomized svd is used.
#'
#' @param p       int, optional \cr
#'                oversampling parameter for \eqn{rsvd}  (default \eqn{p=0}), see \code{\link{rsvd}}.
#'
#' @param q       int, optional \cr
#'                number of power iterations  for \eqn{rsvd} (default \eqn{q=1}), see \code{\link{rsvd}}.
#'
#' @param trace   bool, optional \cr
#'                print progress.
#'
#' @param ...     arguments passed to or from other methods, see \code{\link{rsvd}}.
#'
#' @param ................. .
#'
#' @return \code{rrpca} returns a list with class \eqn{rrpca} containing the following components:
#'    \item{L}{  array_like \cr
#'              Low-rank component, array of shape \eqn{(m, n)}.
#'    }
#'    \item{S}{  array_like \cr
#'               Sparse component, array of shape \eqn{(m, n)}.
#'    }
#'
#'    \item{k}{  int \cr
#'               target-rank used for the final iteration.
#'    }
#'
#'    \item{err}{  vector \cr
#'               Frobenious error archieved by each iteration.
#'    }
#'
#'    \item{.................}{.}
#'
#'
#'
#' @note  ...
#'
#' @author N. Benjamin Erichson, \email{nbe@st-andrews.ac.uk}
#'
#' @references
#' \itemize{
#'   \item  [1] Lin, Zhouchen, Minming Chen, and Yi Ma.
#'          "The augmented lagrange multiplier method for exact
#'          recovery of corrupted low-rank matrices." (2010).
#'          (available at arXiv \url{http://arxiv.org/abs/1009.5055}).
#'   \item  [2] Candes, Emmanuel J., et al.
#'          "Robust principal component analysis?."
#'          Journal of the ACM (JACM) 58.3 (2011).
#' }
#'
#' @examples
#' library(rsvd)
#'
#' # Create toy video
#' # background frame
#' xy <- seq(-50, 50, length.out=100)
#' mgrid <- list( x=outer(xy*0,xy,FUN="+"), y=outer(xy,xy*0,FUN="+") )
#' bg <- 0.1*exp(sin(-mgrid$x**2-mgrid$y**2))
#' toyVideo <- matrix(rep(c(bg), 100), 100*100, 100)
#'
#' # add moving object
#' for(i in 1:90) {
#'   mobject <- matrix(0, 100, 100)
#'   mobject[i:(10+i), 45:55] <- 0.2
#'   toyVideo[,i] =  toyVideo[,i] + c( mobject )
#' }
#'
#' # Foreground/Background separation
#' out <- rrpca(toyVideo, k=1, p=5, q=1, svdalg='rsvd', trace=TRUE)
#'
#' # Display results of the seperation for the 10th frame
#' par(mfrow=c(1,4))
#' image(matrix(bg, ncol=100, nrow=100)) #true background
#' image(matrix(toyVideo[,10], ncol=100, nrow=100)) # frame
#' image(matrix(out$L[,10], ncol=100, nrow=100)) # seperated background
#' image(matrix(out$S[,10], ncol=100, nrow=100)) #seperated foreground

#' @export
rrpca <- function(A, k=NULL, lamb=NULL, gamma=1.25, rho=1.5, maxiter=50, tol=1.0e-3, svdalg='auto', p=10, q=1, trace=FALSE, ...) UseMethod("rrpca")

#' @export
rrpca.default <- function(A, k=NULL, lamb=NULL, gamma=1.25, rho=1.5, maxiter=50, tol=1.0e-3, svdalg='auto', p=10, q=1, trace=FALSE, ...) {
  #*************************************************************************
  #***        Author: N. Benjamin Erichson <nbe@st-andrews.ac.uk>        ***
  #***                              <2016>                               ***
  #***                       License: BSD 3 clause                       ***
  #*************************************************************************
  A <- as.matrix(A)
  m <- nrow(A)
  n <- ncol(A)

  rrpcaObj = list(L = matrix(0, nrow = m, ncol = n),
                  S = matrix(0, nrow = m, ncol = n),
                  k = k,
                  lamb = lamb,
                  gamma = gamma,
                  rho = rho,
                  err = NULL)


  #Set target rank
  if(is.null(rrpcaObj$k)) rrpcaObj$k <- 2
  if(rrpcaObj$k>n) rrpcaObj$k <- n
  if(rrpcaObj$k<1) stop("Target rank is not valid!")

  unobserved = is.na(A)
  A[unobserved] <- 0

  # Set lambda, gamma, rho
  if(is.null(rrpcaObj$lamb)) rrpcaObj$lamb <- max(m,n)^-0.5
  if(is.null(rrpcaObj$gamma)) rrpcaObj$gamma <- 1.25
  if(is.null(rrpcaObj$rho)) rrpcaObj$rho <- 1.5

  # Compute matrix norms
  spectralNorm <- switch(svdalg,
                    svd = norm(A, "2"),
                    rsvd = rsvd(A, k=1, p=5, q=0, nu=0, nv=0)$d,
                    auto = rsvd(A, k=1, p=5, q=0, nu=0, nv=0)$d,
                    stop("Selected SVD algorithm is not supported!")
  )

  infNorm <- norm( A , "I") / rrpcaObj$lamb
  dualNorm <- max( spectralNorm , infNorm)
  froNorm <- norm( A , "F")

  # Normalize A
  Y <- A / dualNorm

  # Computing further tuning parameter
  mu <- rrpcaObj$gamma / spectralNorm
  mubar <- mu * 1e7
  mu <- min( mu*rrpcaObj$rho , mubar )
  muinv <- mu**-1

  rrpcaObj$niter <- 1
  err <- 1
  while(err > tol && rrpcaObj$niter <= maxiter) {

      #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      # Update S using soft-threshold
      #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      epsi = rrpcaObj$lamb*muinv
      tempS = A - rrpcaObj$L + muinv*Y
      rrpcaObj$S = matrix(0, nrow = m, ncol = n)

      idxL <- which(tempS < -epsi)
      idxH <- which(tempS > epsi)
      rrpcaObj$S[idxL] <- tempS[idxL]+epsi
      rrpcaObj$S[idxH] <- tempS[idxH]-epsi

      #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      #Singular Value Decomposition
      #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      if(svdalg=='auto'){
        if(rrpcaObj$k < (n/1.5)) {svdalg='rsvd'} else svdalg='svd'
      }
      svd_out <- switch(svdalg,
                        svd = svd(A - rrpcaObj$S + muinv*Y),
                        rsvd = rsvd(A - rrpcaObj$S + muinv*Y, k=(rrpcaObj$k+p), p=0, q=q, ...),
                        stop("Selected SVD algorithm is not supported!")
      )

      #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      # Predict optimal rank and update
      #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      kopt = sum(svd_out$d > muinv)
      if(kopt <= rrpcaObj$k){
        rrpcaObj$k = min(kopt+1, ncol(svd_out$u))
      } else {
        rrpcaObj$k = min(kopt + round(0.05*n), ncol(svd_out$u))
      }

      #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      # Truncate SVD and update L
      #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      # rrpcaObj$L =  svd_out$u[,1:rrpcaObj$k] %*% diag(svd_out$d[1:rrpcaObj$k] - muinv, nrow=rrpcaObj$k, ncol=rrpcaObj$k)  %*% t(svd_out$v[,1:rrpcaObj$k])
      rrpcaObj$L =  t( t(svd_out$u[,1:rrpcaObj$k]) * (svd_out$d[1:rrpcaObj$k]- muinv) ) %*% t(svd_out$v[,1:rrpcaObj$k])

      #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      # Compute error
      #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      Z = A - rrpcaObj$L - rrpcaObj$S
      Y = Y + mu * Z

      err = norm( Z , 'F') / froNorm
      rrpcaObj$err <- c(rrpcaObj$err, err)

      if(trace==TRUE){
        cat('\n', paste0('Iteration: ', rrpcaObj$niter ), paste0('     k = ', rrpcaObj$k ),  paste0('      Fro. error = ', rrpcaObj$err[rrpcaObj$niter] ))
        }

      #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      # Update mu
      #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      mu = min(mu*rrpcaObj$rho, mubar);
      muinv = 1 / mu

      rrpcaObj$niter = rrpcaObj$niter + 1

  }# End while loop

  class(rrpcaObj) <- "rrpca"
  return( rrpcaObj )

}



