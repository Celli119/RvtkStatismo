#' calculate or modify a probablistic PCA based on 3D-coordinates
#'
#' calculate or modify a probablistic PCA based on 3D-coordinates
#' 
#' @encoding utf8
#' @param x array of dimensions k x 3 x n, where k=number of coordinates and n=sample size -  or a list containing triangular meshes. 
#' @param align logical: if TRUE, the data will be aligned first
#' @param use.lm integer vector: specifies the indices of the points that are to be used in the constrained model
#' @param deselect logical: if TRUE, \code{use.lm} references the missing coordinates instead of the present ones.
#' @param sigma estimate of error variance (sensible is a value estimating coordinate error in terms of observer error)
#' @param exVar numeric value with \code{0 < exVar <= 1} specifying the PCs to be included by their cumulative explained Variance
#' @param scale logical: allow scaling in Procrustes fitting
#' @param representer a triangular mesh, where the vertices correspond to the coordinates in \code{array}, leave NULL for pointclouds.
#' @param model object of class \code{pPCA}
#' @return returns a probabilistic PCA model as S4 class "pPCA" (see \code{\link{pPCA-class}}).
#' \code{UpdateModel} is used to modify existing models by changing sigma and exVar.
#'
#' 
#' 
#' 
#' @examples
#' require(Morpho)
#' data(boneData)
#' model <- pPCA(boneLM[,,])
#' ## change parameters without recomputing Procrustes fit
#' model1 <- UpdateModel(model, sigma=1, exVar=0.8)
#'
#' 
#' @references
#' \enc{Lüthi}{Luethi} M, Albrecht T, Vetter T. 2009. Probabilistic modeling and visualization of the flexibility in morphable models. In: Mathematics of Surfaces XIII. Springer. p 251-264
#' 
#' @importFrom Morpho ProcGPA rotonmat arrMean3 vecx rotonto rotreverse
#' @importFrom Rvcg vcgUpdateNormals
#' @name pPCA
#' @rdname pPCA
#' @export
pPCA <- function(x, align=FALSE,use.lm=NULL,deselect=FALSE,sigma=NULL,exVar=1,scale=FALSE,representer=NULL) {
    if (is.list(x)) {
        if (is.null(representer))
            representer <- x[[1]]
        x <- meshlist2array(x)
    }
    if (align) {
        procMod <- rigidAlign(x,scale=scale,use.lm=use.lm,deselect=deselect)
    } else {
        procMod <- list(rotated=x)
    }
    if (is.null(sigma))
        sigma <- numeric(0)
    procMod$mshape <- NULL
    rawdata <- vecx(procMod$rotated,byrow=T)
    PCA <- prcomp(rawdata,tol = sqrt(.Machine$double.eps)) ## calculate PCA
    PCA$scale <- NULL
    sds <- PCA$sdev^2
    good <- which(sds > 1e-13)
    sds <- sds[good] ## remove PCs with very little variability
    PCA$rotation <- PCA$rotation[,good,drop=FALSE]
    dimnames(PCA$rotation) <- NULL
    PCA$sdev <- PCA$sdev[good]
    PCA$x <- 0
    PCA <- unclass(PCA)
    if (is.null(representer) || is.matrix(representer))
        representer <- list(vb=t(arrMean3(procMod$rotated)),it=matrix(0,3,0))
    model <- new("pPCA",PCA=PCA,representer=representer,rawdata=sweep(rawdata,2,colMeans(rawdata)))
    SetScale(model) <- scale
    model <- UpdateModel(model,sigma=sigma,exVar=exVar)
    if (is.null(dimnames(x)[[3]]))
        mynames <- paste0("specimen_",(1:dim(x)[3]))
    else
        mynames <- dimnames(x)[[3]]
    modinfonames <- names2modelinfo(mynames)
    SetModelDataInfo(model) <- modinfonames
    return(model)

}

###Modify an existing pPCA model
#' @rdname pPCA
#' @export
setGeneric("UpdateModel", function(model,sigma=NULL,exVar=1) {
    standardGeneric("UpdateModel")
})

#' @rdname pPCA
setMethod("UpdateModel", signature(model="pPCA"), function(model,sigma=NULL,exVar=1) {
    k <- ncol(model@representer$vb)
    PCA <- model@PCA
    if (length(model@sigma))
        sds <- calcSdev(model)^2
    else
        sds <- PCA$sdev^2
    sdsum <- sum(sds)
    sdVar <- sds/sdsum
    sdCum <- cumsum(sdVar)
    usePC <- which(sdCum <= exVar)
    if (!length(sigma))
        sigma <- 1/(3*k)*sum(sds[-usePC]) ##estimate sigma from remaining Variance
    if (sigma >= sdsum) {
        warning(paste("sigma > overall variance set to",sdsum/2))
        sigma <- sdsum/2
    }
    sigest <- (sds - sigma)
    sigest <- sigest[which(sigest > 0)]
    usePC <- 1:max(1,min(length(usePC),length(sigest)))
    SetNoiseVariance(model) <- sigma
    PCA$rotation <- PCA$rotation[,usePC,drop=FALSE]
    PCA$sdev <- sqrt(sigest[usePC])
    SetPCA(model) <- PCA
    if (ncol(model@rawdata) > 0) {
        PCA$x <- (model@rawdata%*%t(GetProjectionMatrix(model)))[,usePC,drop=FALSE]
        dimnames(PCA$x) <- NULL
  }  else
        PCA$x <- matrix(0,0,0)
    SetPCA(model) <- PCA
    return(model)
})


print.pPCA <- function(x, digits = getOption("digits"), Variance=TRUE,...){
    cat(paste("   sigma =",x@sigma,"\n"))
    cat(paste(" first",length(x@PCA$sdev),"PCs used\n"))
    if (Variance) {
        cat("\n\n Model Variance:\n")
        print(createVarTable(x@PCA$sdev,square=TRUE))
    }
}
setMethod("show", "pPCA", function(object){print.pPCA(object)})


#' calculate probability/coefficients for a matrix/mesh given a statistical model
#'
#' calculate probability for a matrix/mesh given a statistical model
#' @param x matrix or mesh3d
#' @param model a model of class pPCA
#' @param align logical: if TRUE the data will be aligned to the model's mean
#' @param lmDataset optional: landmarks on the dataset used for alignment.
#' @param lmModel optional: landmarks on the model's mean used for alignment.
#' @return \code{getDataLikelihood} returns a probability, while \code{getCoefficients} returns the (scaled) scores in the pPCA space.
#' @details \code{getDataLikelihood} estimates the likelihood of a dataset for belonging to the model by exploiting the \eqn{\chi^2}{Chi-square}-distribution of the (squared) Mahalanobisdistance, which, in turn, is simply the squared norm of the sample's coefficients in the latent space.
#' @export
getDataLikelihood <- function(x,model,align=FALSE, lmDataset=NULL, lmModel=NULL) UseMethod("getDataLikelihood")

#' @rdname getDataLikelihood
#' @export
getDataLikelihood.matrix <- function(x,model,align=FALSE, lmDataset=NULL, lmModel=NULL) {
    mshape <- getMeanMatrix(model,transpose=TRUE)
    if (!is.null(lmDataset) && !is.null(lmModel))
        hasLM <- TRUE
    if (align) {
        if (!hasLM) {
            rotsb <- rotonto(mshape,x,scale=model@scale,reflection = F)
            sb <- rotsb$yrot
        } else {
            rotsb <- rotonto(lmModel,lmDataset,scale=model@scale,reflection=F)
            sb <- rotonmat(x,lmDataset,rotsb$yrot)
        }
    } else {
        sb <- x
    }
    sbres <- sb-mshape
    alpha <- GetProjectionMatrix(model)%*%as.vector(t(sbres))
    sdl <- length(model@PCA$sdev)
    probs <- sum(alpha^2)
    probout <- pchisq(probs,lower.tail = F,df=sdl)
    return(probout)
}

#' @rdname getDataLikelihood
#' @export
getDataLikelihood.mesh3d <- function(x,model,align=FALSE,lmDataset=NULL, lmModel=NULL) {
    x <- vert2points(x)
    out <- getDataLikelihood(x,model=model,align=align, lmDataset=lmDataset, lmModel=lmModel)
    return(out)
}

#' @rdname getDataLikelihood
#' @export
getCoefficients <- function(x, model,align=TRUE, lmDataset=NULL, lmModel=NULL) {
    out <- PredictSample(model,x,FALSE,lmDataset=lmDataset, lmModel=lmModel,coeffs=NULL,align=align)
    return(out)
}

#' get per coordinate variance from a statistical model
#'
#' get per coordinate variance from a statistical model
#'
#' @encoding utf8
#' @param model object of class pPCA
#' @note calculates the per-coordinate variance as described in Luethi(2009)
#' @references \enc{Lüthi}{Luethi} M, Albrecht T, Vetter T. 2009. Probabilistic modeling and visualization of the flexibility in morphable models. In: Mathematics of Surfaces XIII. Springer. p 251-264
#' @export
getCoordVar <- function(model) {
    if (!inherits(model,"pPCA"))
        stop("please provide model of class pPCA")
    W <- GetPCABasisMatrix(model)
    m <- ncol(model@representer$vb)
    cov0 <- rowSums(W*W)
    mat <- matrix(cov0,nrow=(length(cov0)/m),m,byrow = F)+model@sigma
    cov0 <- apply(mat,2,function(x) x <- sqrt(sum(x)))
    return(cov0)
}

