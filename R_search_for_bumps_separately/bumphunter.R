setMethod("MultiTargetBumphunter", signature(object = "matrix"),
          function(object, design, chr=NULL, pos, cluster=NULL,
                   coef=2, cutoff=NULL, pickCutoff=FALSE, pickCutoffQ=0.99,
                   maxGap=500,
                   nullMethod=c("permutation","bootstrap"), smooth=FALSE,
                   smoothFunction=locfitByCluster,
                   useWeights=FALSE, B=ncol(permutations), permutations=NULL,
                   verbose=TRUE, nullmodel_coef=NULL, computePValuesJointly = F, 
                   bumpDirections = NULL, 
                   SamplesToDetermineDirection = NULL, 
                   SamplesContraintedByDistribution = NULL,
                   distribution = NULL,
                   ...){
              nullMethod  <- match.arg(nullMethod)
              if(missing(design)) stop("design must be specified")
              if(missing(pos)) stop("If object is a matrix, pos must be specified")
              MultiTargetBumphunterEngine(object, design=design, chr=chr, pos,
                               cluster=cluster,
                               coef=coef,
                               cutoff=cutoff, pickCutoff=pickCutoff,
                               pickCutoffQ=pickCutoffQ,
                               maxGap=maxGap,nullMethod=nullMethod,
                               smooth=smooth,
                               smoothFunction=smoothFunction,
                               useWeights=useWeights, B=B,
                               permutations=permutations,
                               verbose=verbose, 
                               nullmodel_coef=nullmodel_coef, 
                               computePValuesJointly = computePValuesJointly, 
                               bumpDirections = bumpDirections, 
                               SamplesToDetermineDirection = SamplesToDetermineDirection, 
                               SamplesContraintedByDistribution = SamplesContraintedByDistribution,
                               distribution = distribution,
                               ...)
          })


MultiTargetBumphunterEngine<-function(mat, design, chr = NULL, pos,
                           cluster = NULL, coef = 2,
                           cutoff = NULL, pickCutoff = FALSE,
                           pickCutoffQ = 0.99,
                           maxGap = 500,
                           nullMethod = c("permutation","bootstrap"),
                           smooth = FALSE,
                           smoothFunction = locfitByCluster,
                           useWeights = FALSE,
                           B = ncol(permutations),
                           permutations = NULL,
                           verbose = TRUE, 
                           nullmodel_coef = NULL, 
                           computePValuesJointly = F, 
                           bumpDirections = NULL, 
                           SamplesToDetermineDirection = NULL, 
                           SamplesContraintedByDistribution = NULL,
                           distribution = NULL,
                           ...){
    nullMethod  <- match.arg(nullMethod)
    
    pickCutoff=FALSE
    cluster <- NULL
    Index <- NULL
    smooth <- FALSE
    permutations <- NULL
    useWeights = FALSE
    verbose = TRUE
    nullMethod <- "permutation"
    if (is.null(B))  B = 0
    if (!is.matrix(permutations) & !is.null(permutations)) stop("permutations must be NULL or a matrix.")
    if (!is.null(permutations)) {
        if (nrow(design) != nrow(permutations))
            stop("Number of rows of 'design' must match number of rows of 'permutations'.")
        if (B != ncol(permutations)) {
            warning("Ignoring the supplied B. Using 'ncol(permutations)' instead.")
            B = ncol(permutations)
        }
    }
     if (ncol(design[,-coef]) > 1 & B > 0 & nullMethod == "permutation"){
        message("[bumphunterEngine] The use of the permutation test is not recommended with multiple covariates, (ncol(design[,-coef]) > 1). Consider changing 'nullMethod' changed to 'bootstrap' instead. See vignette for more information.")
        warning("The use of the permutation test is not recommended with multiple covariates, (ncol(design[,-coef]) > 1). Consider changing 'nullMethod' changed to 'bootstrap' instead. See vignette for more information.")
    }
    if (!is.matrix(mat))
        stop("'mat' must be a matrix.")
    if (ncol(mat) != nrow(design))
        stop("Number of columns of 'mat' must  match number of rows of 'design'")
    if (B < 0)
        stop("'B' has to be an integer greater or equal to zero")
    if (!(is.null(cutoff) || length(cutoff) %in% 1:2))
        stop("'cutoff' has to be either NULL or a vector of length 1 or 2")
    if (length(cutoff) == 2)
        cutoff <- sort(cutoff)
    if (is.null(cutoff) && !pickCutoff)
        stop("Must pick a cutoff, either using 'cutoff' or 'pickCutoff'")
    if (!is.null(cutoff) && pickCutoff) {
        pickCutoff <- FALSE
        warning("'cutoff' was supplied so ignoring 'pickCutoff=TRUE'")
    }
    if (pickCutoff && (length(pickCutoffQ) != 1 || pickCutoff <  0 || pickCutoffQ > 1))
        stop("Using `pickCutoff = TRUE' requires that 'pickCutoffQ' is a single number between 0 and 1")
    if (pickCutoff && B < 1)
        stop("Must do at least one permution to pick a cutoff")
    if (!getDoParRegistered())
        registerDoSEQ()
    workers <- getDoParWorkers()
    backend <- getDoParName()
    version <- getDoParVersion()
    subverbose <- max(as.integer(verbose) - 1L, 0)
    if (verbose) {
        if (workers == 1) {
            mes <- "[bumphunterEngine] Using a single core (backend: %s, version: %s)."
            message(sprintf(mes, backend, version))
        }
        else {
            mes <- "[bumphunterEngine] Parallelizing using %s workers/cores (backend: %s, version: %s)."
            message(sprintf(mes, workers, backend, version))
        }
    }
    if (is.null(chr))
        chr <- rep("Unspecified", length(pos))
    if (is.factor(chr))
        chr <- as.character(chr)
    if (is.null(cluster))
        cluster <- clusterMaker(chr, pos, maxGap = maxGap)
    if (verbose)
        message("[bumphunterEngine] Computing coefficients.")
    if (useWeights & smooth) { 
        tmp <- MultiTargetGetEstimate(mat = mat, design = design,
                            coef = coef, full = TRUE)
        rawBeta <- tmp$coef
        weights <- tmp$sigma
        rm(tmp)
    } else {
        rawBeta <- MultiTargetGetEstimate(mat = mat, design = design, coef = coef,
            full = FALSE)
        weights <- NULL
    }
    if (smooth) {
        if (verbose)
            message("[bumphunterEngine] Smoothing coefficients.")
        beta <- smoother(y = rawBeta, x = pos, cluster = cluster,
            weights = weights, smoothFunction = smoothFunction,
            verbose = subverbose, ...)
        Index <- which(beta$smoothed)
        beta <- beta$fitted
    } else {
        beta <- rawBeta
        Index <- seq(getLengthMatrixOrVector(beta))
    }
    #if (!is.null(nullmodel_coef))
       # B = 1
    if (B > 0 || !is.null(nullmodel_coef)) {
      if (!is.null(nullmodel_coef)){
        if (verbose)
          message("[bumphunterEngine] Performing ", B, " permutations with nullmodel coefficients")
#         if (useWeights && smooth) {
#           tmp <- MultiTargetGetEstimate(mat, design, coef, B,
#                                         permutations, full = TRUE)
#           permRawBeta <- tmp$coef
#           weights <- tmp$sigma
#           rm(tmp)
#         }
#         else {
          
          null_model_matrix <- rep(nullmodel_coef, ceiling((nrow(design)- length(nullmodel_coef))/ length(nullmodel_coef)))[1:(nrow(design)- length(nullmodel_coef))]
          null_model_matrix <- c(null_model_matrix, nullmodel_coef)
          null_model_matrix <- mat[, null_model_matrix]

          permRawBeta <- MultiTargetGetEstimate(null_model_matrix, design, coef, B, permutations, full = FALSE)

          weights <- NULL
      #}
          NullBeta<-permRawBeta  
        } else {
          if (nullMethod == "permutation"){
            if (verbose)
                message("[bumphunterEngine] Performing ", B, " permutations.")
            if (useWeights && smooth) {
                tmp <- MultiTargetGetEstimate(mat, design, coef, B,
                                    permutations, full = TRUE)
                permRawBeta <- tmp$coef
                weights <- tmp$sigma
                rm(tmp)
            }
            else {
                permRawBeta <- MultiTargetGetEstimate(mat, design, coef, B, permutations, full = FALSE)
                weights <- NULL
            }
            NullBeta<-permRawBeta	
        }
        if (nullMethod == "bootstrap"){
            message("[bumphunterEngine] Performing ", B, " bootstraps.")
            qr.X <- qr(design)
            resids <- t(tcrossprod( diag(nrow(design)) - tcrossprod(qr.Q(qr.X)),  mat))

            ##rescale residuals
            h <- diag(tcrossprod(qr.Q( qr(design))))
            resids <- t(t(resids)/sqrt(1-h))

            ##create the null model to which we add bootstrap resids
            design0 <- design[,-coef,drop=FALSE]
            qr.X0 <- qr(design0)
            null <- t(tcrossprod(tcrossprod(qr.Q(qr.X0)), mat))

            ##Now do the boostraps
            chunksize <- ceiling(B/workers) 
            bootIndexes<-replicate(B, sample(1:ncol(mat),replace=TRUE),simplify=TRUE)
            
            tmp <- foreach(bootstraps = iter(bootIndexes, by = "column", chunksize = chunksize),
                           .combine = "cbind", .packages = "bumphunter") %dorng% {
                          
                             do.call(cbind, lapply(as.list(data.frame(bootstraps)), function(bootIndex){
                                   ##create a null model
                                   matstar <- null+resids[,bootIndex]
                                   ##compute the null beta estimate
                                   nullbetas <- t(backsolve(qr.R(qr.X),crossprod(qr.Q(qr.X),t(matstar)))[coef,])
                                   if (useWeights){
                                       ##compute sigma
                                     
                                      # !!! modify sigma here?
                                       sigma <- rowSums(t(tcrossprod( diag(nrow(design)) - tcrossprod(qr.Q(qr.X)),  matstar))^2)
                                       sigma <-
                                           sqrt(sigma/(nrow(design)-qr.X$rank))
                                       outList <- list(coef=nullbetas,sigma=sigma)
                                   } else {
                                       outList <- nullbetas
                                   }
                                   return(outList)
                               }))
                           }
            
            if (useWeights && smooth) {
                # !!! Make sure that this works!
                bootRawBeta <- do.call(Map, c(cbind, tmp))$coef
                weights <- do.call(Map, c(cbind, tmp))$sigma
            } else {
                bootRawBeta <- tmp
                weights <- NULL
            }
            NullBeta<-bootRawBeta
            rm(tmp)
            rm(bootRawBeta)
        }}
        if (verbose)
            message("[bumphunterEngine] Computing marginal ",nullMethod," p-values.")
        sumGreaterOrEqual <- rowSums(greaterOrEqual(abs(NullBeta),
            abs(as.vector(rawBeta))))
        pvs <- (sumGreaterOrEqual + 1L)/(B + 1L)
        if (smooth) {
            if (verbose)
                message("[bumphunterEngine] Smoothing ",nullMethod," coefficients.")
            permBeta <- smoother(y = NullBeta, x = pos, cluster = cluster,
                weights = weights, smoothFunction = smoothFunction,
                verbose = subverbose, ...)$fitted
        } else permBeta <- NullBeta
        if (is.null(cutoff))
            cutoff <- quantile(abs(permBeta), pickCutoffQ, na.rm = TRUE)
        if (verbose)
            message(sprintf("[bumphunterEngine] cutoff: %s",
                round(cutoff, 3)))
    } 
    if (verbose)
        message("[bumphunterEngine] Finding regions.")
    tabs <- list()
    for (j in 1:length(coef))
    {
      tabs[[j]] <- regionFinder(x = beta[,j], chr = chr, pos = pos, cluster = cluster,
        cutoff = cutoff, ind = Index, verbose = FALSE, addMeans = T, mat=mat, design=design, maxGap=maxGap)
        
      if (nrow(tabs[[j]]) == 0) {
          if (verbose)
              message("[bumphunterEngine] No bumps found!")
          return(list(table = NA, coef = rawBeta, fitted = beta,
              pvaluesMarginal = NA))
      } else {
          if (verbose)
              message(sprintf("[bumphunterEngine] Found %s bumps.",
                  nrow(tabs[[j]])))
      }
    
      #if (B < 1) {
      #    return(list(table = tabs[[j]], coef = rawBeta, fitted = beta,
      #        pvaluesMarginal = NA))
      #}
    }
    if (verbose)
        message("[bumphunterEngine] Computing regions for each ",nullMethod,".")
    chunksize <- ceiling(B * length(coef)/workers)
    subMat <- NULL
    
    ptime2 <- proc.time()
    nulltabs <- foreach(subMat = iter(permBeta, by = "col", chunksize = chunksize),
          .combine = "c") %dorng% {
            
          source("bumphunter/R/regionFinder.R")
          source("bumphunter/R/utils.R")
          
          apply(subMat, 2, regionFinder, chr = chr, pos = pos,
              cluster = cluster, cutoff = cutoff, ind = Index,
              verbose = FALSE,  addMeans = T, mat=mat, design=design, maxGap=maxGap)
      }
    attributes(nulltabs[[j]])[["rng"]] <- NULL
    
    print(proc.time()-ptime2)

    if (verbose)
        message("[bumphunterEngine] Estimating p-values and FWER.")
    D <- L <- V <- A <- as.list(rep(0, B * length(coef)))
    for (i in 1:(B * length(coef))) {
        nulltab <- nulltabs[[i]]
        current_coef <- if (i %% length(coef) == 0) length(coef) else (i %% length(coef))
        
        if (nrow(nulltab) > 0) {
            # Values per permutation
            # If there are n covariates of interest, 
            # then every n-th permutation corresponds to the n-th covariate
            L[[i]] <- nulltab$L
            V[[i]] <- nulltab$value
            A[[i]] <- nulltab$area

            if (computePValuesJointly)
            {
               D[[i]] <- nulltab[,paste0("covariate.diff", 1:length(coef))]
            }
            else
            {
              D[[i]] <- nulltab[,paste0("covariate.diff", current_coef)]
            }
        }
    }

##    ptime1 <- proc.time()
    if (computePValuesJointly)
    {
      ptime2 <- proc.time()
      comp <- computation.tots.jointly(tabs, V = V, L = L, A = A, D = D,
         maxGap=maxGap, chr=chr, pos=pos, mat=mat, beta = beta, 
         workers = workers, nulltabs = nulltabs, coef=coef,
         verbose = verbose,
         bumpDirections, SamplesToDetermineDirection,
         SamplesContraintedByDistribution, distribution)
      if (verbose)
      {
        message("[bumphunterEngine] Total time for computation:")
        print(proc.time()-ptime2)
      }
      rate1 <- comp$rate1
      pvalues1 <- comp$pvalues1
      ##    ptime2 <- proc.time()
      ##ptime1 <- proc.time()
      rate2 <- comp$rate2
      pvalues2 <- comp$pvalues2
      joined_tabs <- comp$joined_tabs_with_values[[1]]
      joined_tabs <- subset(joined_tabs, select= -c(value, area))
      ##ptime2 <- proc.time()
      joined_tabs$p.value <- pvalues1
      joined_tabs$fwer <- rate1
      joined_tabs$p.valueArea <- pvalues2
      joined_tabs$fwerArea <- rate2
      joined_tabs <- joined_tabs[order(joined_tabs$p.value, -joined_tabs$L), ]
     
      if (verbose)
        message(sprintf("[bumphunterEngine] Found %s joined bumps.",
                        nrow(joined_tabs)))

      tabs <- joined_tabs
    } else {
      for (j in 1:length(coef))
      {
        tab <- tabs[[j]]
        indices <- seq(1, ncol(permBeta), length(coef)) + j - 1
        # If there are n covariates of interest, 
        # then every n-th permutation in V and L corresponds to the n-th covariate
        
        comp <- computation.tots(tab = tab, V = V[indices], L = L[indices], 
                                 D = D[indices], workers, nulltabs = nulltabs[indices], current_covariate=j)
        rate1 <- comp$rate1
        pvalues1 <- comp$pvalues1
    ##    ptime2 <- proc.time()
        ##ptime1 <- proc.time()
        comp <- computation.tots2(tab = tab, A = A[indices], workers, nulltabs = nulltabs[indices])
        rate2 <- comp$rate2
        pvalues2 <- comp$pvalues2
        ##ptime2 <- proc.time()
        tab$p.value <- pvalues1
        tab$fwer <- rate1
        tab$p.valueArea <- pvalues2
        tab$fwerArea <- rate2
        tab <- tab[order(tab$fwer, -tab$area), ]
        tabs[[j]] <- tab
      }
    }
    algorithm <- list(version = packageDescription("bumphunter")$Version,
        coef = coef, cutoff = cutoff, pickCutoff = pickCutoff,
        pickCutoffQ = pickCutoffQ, smooth = smooth, maxGap = maxGap, nullMethod=nullMethod,
        B = B, permutations = permutations, useWeights = useWeights,
        smoothFunction = deparse(substitute(smoothFunction)))
    ret <- list(table = tabs, coef = rawBeta, fitted = beta, pvaluesMarginal = pvs,
        null = list(value = V, length = L), algorithm = algorithm)
    class(ret) <- "bumps"
    return(ret)
}


print.bumps <- function(x, ...) {
    cat(sprintf("a 'bumps' object with %s bumps\n", nrow(x$table)))
}
