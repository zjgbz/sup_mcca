library(PMA)

soft <- function(x,d){
  return(sign(x)*pmax(0, abs(x)-d))
}

l2n <- function(vec){
  a <- sqrt(sum(vec^2))
  if(a==0) a <- .05
  return(a)
}

BinarySearch <- function(argu,sumabs){
  if(l2n(argu)==0 || sum(abs(argu/l2n(argu)))<=sumabs) return(0)
  lam1 <- 0
  lam2 <- max(abs(argu))-1e-5
  iter <- 1
  while(iter < 150){
    su <- soft(argu,(lam1+lam2)/2)
    if(sum(abs(su/l2n(su)))<sumabs){
      lam2 <- (lam1+lam2)/2
    } else {
      lam1 <- (lam1+lam2)/2
    }
    if((lam2-lam1)<1e-6) return((lam1+lam2)/2)
    iter <- iter+1
  }
  warning("Didn't quite converge")
  return((lam1+lam2)/2)
}

df_list2matrix <- function(xlist_input, K) {
  xlist = list()
  for (k in 1:K) {
    if (is.data.frame(xlist_input[[k]])) {
      xlist[[k]] = as.matrix(xlist_input[[k]])
    } else {
      xlist[[k]] = xlist_input[[k]]
    }
  }
  return (xlist)
}

UpdateW <- function(xlist, i, K, sumabsthis, ws, type="standard", ws.final){
  tots <- 0
  for(j in (1:K)[-i]){
    diagmat <- (t(ws.final[[i]])%*%t(xlist[[i]]))%*%(xlist[[j]]%*%ws.final[[j]])
    diagmat[row(diagmat)!=col(diagmat)] <- 0
    tots <- tots + t(xlist[[i]])%*%(xlist[[j]]%*%ws[[j]]) - ws.final[[i]]%*%(diagmat%*%(t(ws.final[[j]])%*%ws[[j]]))
  }
  if(type=="standard"){
    sumabsthis <- BinarySearch(tots, sumabsthis)
    w <- soft(tots, sumabsthis)/l2n(soft(tots, sumabsthis))
  } else {
    tots <- as.numeric(tots)
    tots <- tots/mean(abs(tots)) 
    w <- FLSA(tots,lambda1=sumabsthis,lambda2=sumabsthis)[1,1,]
    flsa.out <- diag.fused.lasso.new(tots,lam1=sumabsthis)
    lam2ind <- which.min(abs(flsa.out$lam2-sumabsthis))
    w <- flsa.out$coef[,lam2ind]
    w <- w/l2n(w)
    w[is.na(w)] <- 0
  }
  return(w)
}

GetCrit <- function(xlist, ws, K){
  crit <- 0
  for(i in 2:K){
    for(j in 1:(i-1)){
      crit <- crit + t(ws[[i]])%*%t(xlist[[i]])%*%xlist[[j]]%*%ws[[j]]
    }
  }
  return(crit)
}

GetCors <- function(xlist, ws, K){
  cors <- 0
  for(i in 2:K){
    for(j in 1:(i-1)){
      thiscor  <-  cor(xlist[[i]]%*%ws[[i]], xlist[[j]]%*%ws[[j]])
      if(is.na(thiscor)) thiscor <- 0
      cors <- cors + thiscor
    }
  }
  return(cors)
}


ftrans <- function(x){ return(.5*log((1+x)/(1-x))) }

sup_MultiCCA.permute <- function(xlist_raw, y, outcome, penalties=NULL, ws=NULL, type="standard", nperms=25, niter=3, trace=TRUE, standardize=TRUE){
  call <- match.call()
  K <- length(xlist_raw)
  for(k in 1:K){
    if(ncol(xlist_raw[[k]])<2) stop("Need at least 2 features in each data set!")
    if(standardize) xlist_raw[[k]] <- scale(xlist_raw[[k]], T, T)
    if (is.matrix(xlist_raw[[k]])) {
      xlist_raw[[k]] = as.data.frame(xlist_raw[[k]])
    }
  }
  if(length(type)==1) type <- rep(type, K) # If type is just a single element, expand to make a vector of length(xlist_raw)
          # Or type can have standard/ordered for each elt of xlist_raw
  if(length(type)!=K) stop("Type must be a vector of length 1, or length(xlist_raw)")
  if(sum(type!="standard" & type!="ordered")>0) stop("Each element of type must be standard or ordered.")

  # if (!is.data.frame(xlist_raw)) {
  #   stop("xlist before selection should be dataframe.")
  # }

  filter_out = MultiCCA.Phenotype.ZeroSome(xlist_raw, y, qt=.8, cens=NULL, outcome=outcome, type)
  xlist_input = filter_out$xlist_sel
  xlist = df_list2matrix(xlist_input, K)
  feature_dropped = filter_out$feature_dropped
  # print("step I")
  # print(dim(xlist[[1]]))
  # print(dim(xlist[[2]]))

  if(is.null(penalties)){
    if(sum(type=="ordered")==K) stop("Do not run MultiCCA.permute with only ordered data sets and penalties unspecified,
                                      since we only choose tuning the parameter via permutations when type='standard'.")
    penalties <- matrix(NA, nrow=K, ncol=10)
    for(k in 1:K){
      if(type[k]=="ordered"){
        lam <- ChooseLambda1Lambda2(svd(xlist[[k]])$v[,1])
        penalties[k,] <- lam
      } else {
        penalties[k,] <- pmax(seq(.1, .8, len=10) * sqrt(ncol(xlist[[k]])),1.1)
      }
    }
  }
  numnonzeros <- NULL
  if(!is.matrix(penalties)) penalties <- matrix(1,nrow=K,ncol=1)%*%matrix(penalties,nrow=1)
  permcors <- matrix(NA, nrow=nperms, ncol=ncol(penalties))
  cors <- numeric(ncol(penalties)) 
  for(i in 1:ncol(penalties)){
    out <- MultiCCA(xlist, penalty=penalties[,i], niter=niter, type=type, ws=ws, trace=trace)
    # ws_tmp = out$ws
    # ws1 = ws_tmp[[1]]
    # ws2 = ws_tmp[[2]]
    # print("step II")
    # print(dim(ws1))
    # print(dim(ws2))
    # print(dim(xlist[[1]]))
    # print(dim(xlist[[2]]))
    cors[i] <- GetCors(xlist, out$ws, K)
    numnonzeros <- c(numnonzeros, sum(out$numnonzeros))
    ws.init  <- out$ws.init
  }
  cat(fill=TRUE)
  for(j in 1:nperms){
    if(trace) cat("Permutation ", j, "of " , nperms ,fill=TRUE)
    xlistperm <- xlist
    for(k in 1:K){
      xlistperm[[k]] <- xlistperm[[k]][sample(1:nrow(xlistperm[[k]])),]
    }
    for(i in 1:ncol(penalties)){
      out <- MultiCCA(xlistperm, penalty=penalties[,i], niter=niter, type=type, ws=ws, trace=FALSE)
      permcors[j,i] <- GetCors(xlistperm, out$ws, K)
    }
  }
  pvals =zs =  NULL
  for(i in 1:ncol(penalties)){
    pvals <- c(pvals, mean(permcors[,i]>=cors[i]))
    zs <- c(zs, (cors[i]-mean(permcors[,i]))/(sd(permcors[,i])+.05))
  }
  if(trace) cat(fill=TRUE)
  out <- list(pvals=pvals, zstat=zs, bestpenalties=penalties[,which.max(zs)], cors=cors, corperms=permcors, numnonzeros=numnonzeros, ws.init=ws.init, call=call, penalties=penalties, type=type, nperms=nperms, xlist=xlist_input, feature_dropped=feature_dropped)
  class(out) <- "sup_MultiCCA.permute"
  return(out)
}

sup_MultiCCA <- function(xlist_raw, xlist_input, feature_dropped, penalty=NULL, ws=NULL, niter=25, type="standard", ncomponents=1, trace=TRUE, standardize=TRUE){
  K <- length(xlist_input)
  # Newly added
  if (!is.data.frame(xlist_input[[1]]) | !is.data.frame(xlist_raw[[1]])) {
    stop("xlist before and after selection should be dataframe.")
  }
  xlist = df_list2matrix(xlist_input, K)

  for(i in 1:K){
    if(ncol(xlist[[i]])<2) stop("Need at least 2 features in each data set.")
  }
  call <- match.call()

  if(length(type)==1) type <- rep(type, K) # If type is just a single element, expand to make a vector of length(xlist)
          # Or type can have standard/ordered for each elt of xlist
  if(length(type)!=K) stop("Type must be a vector of length 1, or length(xlist)")
  if(sum(type!="standard" & type!="ordered")>0) stop("Each element of type must be standard or ordered.")
  for(k in 1:K){
    if(standardize) xlist[[k]] <- scale(xlist[[k]], T, T)
  }
  if(!is.null(ws)){
    makenull <- FALSE
    for(i in 1:K){
      if(ncol(ws[[i]])<ncomponents) makenull <- TRUE
    }
    if(makenull) ws <- NULL
  }
  if(is.null(ws)){
    ws <- list()
    for(i in 1:K) ws[[i]] <- matrix(svd(xlist[[i]])$v[,1:ncomponents], ncol=ncomponents)
  }
  if(is.null(penalty)){
    penalty <- rep(NA, K)
    penalty[type=="standard"] <- 4 # this is the default value of sumabs
    for(k in 1:K){
      if(type[k]=="ordered"){
        v <- svd(xlist[[k]])$v[,1]
        penalty[k] <- ChooseLambda1Lambda2(v)
      }
    }
  }
  ws.init <- ws
  if(length(penalty)==1) penalty <- rep(penalty, K)
  if(sum(penalty<1 & type=="standard")) stop("Cannot constrain sum of absolute values of weights to be less than 1.")
  for(i in 1:length(xlist)){
    if(type[i]=="standard" && penalty[i]>sqrt(ncol(xlist[[i]]))) stop("L1 bound of weights should be no more than sqrt of the number of columns of the corresponding data set.", fill=TRUE)
  }
  ws.final <- list()
  for(i in 1:length(ws)) ws.final[[i]] <- matrix(0, nrow=ncol(xlist[[i]]), ncol=ncomponents)
  cors <- NULL
  for(comp in 1:ncomponents){
    ws <- list()
    for(i in 1:length(ws.init)) ws[[i]] <- ws.init[[i]][,comp]
    curiter <- 1
    crit.old <- -10
    crit <- -20
    storecrits <- NULL
    while(curiter<=niter && abs(crit.old-crit)/abs(crit.old)>.001 && crit.old!=0){
      crit.old <- crit
      crit <- GetCrit(xlist, ws, K)
      storecrits <- c(storecrits,crit)
      if(trace) cat(curiter, fill=FALSE)
      curiter <- curiter+1
      for(i in 1:K){
        ws[[i]] <- UpdateW(xlist, i, K, penalty[i], ws, type[i], ws.final)
      }
    }
    for(i in 1:length(ws)) ws.final[[i]][,comp] <- ws[[i]]
    cors <- c(cors, GetCors(xlist, ws,K))
  }
  ws.final_raw = list()
  cv = list()
  for (i in 1:length(xlist)) {
    ws.final[[i]] = as.data.frame(ws.final[[i]])
    rownames(ws.final[[i]]) = colnames(xlist_input[[i]])
    weight_dropped = as.data.frame(matrix(0, nrow=length(feature_dropped[[i]]), ncol=ncomponents))
    rownames(weight_dropped) = feature_dropped[[i]]
    tmp_ws.final_raw = rbind(ws.final[[i]], weight_dropped)
    tmp_ws.final_raw = tmp_ws.final_raw[colnames(xlist_raw[[i]]), ]
    ws.final_raw[[i]] = as.matrix(tmp_ws.final_raw)
    # ws.final_raw[[i]] = tmp_ws.final_raw
  }
  out <- list(ws=ws.final_raw, ws.init=ws.init, K=K, call=call, type=type, penalty=penalty, cors=cors)
  class(out) <- "sup_MultiCCA"
  return(out)
}

MultiCCA.Phenotype.ZeroSome <- function(xlist,y,qt=.8,cens=NULL,outcome=c("quantitative", "survival", "multiclass"), type){
  outcome <- match.arg(outcome)
  K = length(xlist)
  xlist_sel = list()
  score_list = list()
  feature_dropped = list()
  for(k in 1:K) {
    tmp_x = xlist[[k]]
    if (outcome=="quantitative") {
      score.x <- quantitative.func(t(tmp_x)[,!is.na(y)],y[!is.na(y)])$tt
    } else if (outcome=="survival") {
      score.x <- cox.func(t(tmp_x)[,!is.na(y)],y[!is.na(y)],cens[!is.na(y)])$tt
    } else if (outcome=="multiclass") {
      score.x <- multiclass.func(t(tmp_x)[,!is.na(y)],y[!is.na(y)])$tt
    }
    if(type[k] == "standard"){
      keep.x <- abs(score.x) >= quantile(abs(score.x),qt)
    } else if (type[k] == "ordered") {
      lam <- ChooseLambda1Lambda2(as.numeric(score.x))
      flsa.out <- FLSA(as.numeric(score.x),lambda1=lam, lambda2=lam)
      par(mfrow=c(2,1))
      keep.x <- abs(flsa.out)>=quantile(abs(flsa.out), qt)
      if(mean(keep.x)==1 | mean(keep.x)==0) keep.x <- (abs(score.x) >= quantile(abs(score.x), qt))
    }
    xnew <- tmp_x
    xlist_sel[[k]] = xnew[, keep.x]
    xlist_drop = xnew[,!keep.x]
    feature_dropped[[k]] = colnames(xlist_drop)
    # print(feature_dropped[[k]])
    score_list[[k]] = score.x
  }
  # return(list(xlist_sel=xlist_sel, score_list=score_list))
  return(list(xlist_sel=xlist_sel, feature_dropped=feature_dropped))
}

CCAPhenotypeZeroSome <- function(x,z,y,qt=.8,cens=NULL,outcome=c("quantitative", "survival", "multiclass"), typex,typez){
  outcome <- match.arg(outcome)
  if(outcome=="quantitative"){
    score.x <- quantitative.func(t(x)[,!is.na(y)],y[!is.na(y)])$tt
    score.z <- quantitative.func(t(z)[,!is.na(y)],y[!is.na(y)])$tt
  } else if (outcome=="survival"){
    score.x <- cox.func(t(x)[,!is.na(y)],y[!is.na(y)],cens[!is.na(y)])$tt
    score.z <- cox.func(t(z)[,!is.na(y)],y[!is.na(y)],cens[!is.na(y)])$tt
  } else if (outcome=="multiclass"){
    score.x <- multiclass.func(t(x)[,!is.na(y)],y[!is.na(y)])$tt
    score.z <- multiclass.func(t(z)[,!is.na(y)],y[!is.na(y)])$tt
  }
  if(typex=="standard"){
    keep.x <- abs(score.x)>=quantile(abs(score.x),qt)
  } else if(typex=="ordered"){
    lam <- ChooseLambda1Lambda2(as.numeric(score.x))
    flsa.out <- FLSA(as.numeric(score.x),lambda1=lam, lambda2=lam)
#    diagfl.out <- diag.fused.lasso.new(as.numeric(score.x), lam1=lam)
#    lam2ind <- which.min(abs(diagfl.out$lam2-lam))
#    flsa.out <- diagfl.out$coef[,lam2ind]
    par(mfrow=c(2,1))
    keep.x <- abs(flsa.out)>=quantile(abs(flsa.out), qt)
    if(mean(keep.x)==1 | mean(keep.x)==0) keep.x <- (abs(score.x) >= quantile(abs(score.x), qt))
  }
  if(typez=="standard"){
    keep.z <- abs(score.z)>=quantile(abs(score.z),qt)
  } else if(typez=="ordered"){
    lam <- ChooseLambda1Lambda2(as.numeric(score.z))
    flsa.out <- FLSA(as.numeric(score.z),lambda1=lam, lambda2=lam)
#    diagfl.out <- diag.fused.lasso.new(as.numeric(score.z), lam1=lam)
#    lam2ind <- which.min(abs(diagfl.out$lam2-lam))
#    flsa.out <- diagfl.out$coef[,lam2ind]
    par(mfrow=c(2,1))
    keep.z <- abs(flsa.out)>=quantile(abs(flsa.out), qt)
    if(mean(keep.z)==1 | mean(keep.z)==0) keep.z <- (abs(score.z) >= quantile(abs(score.z), qt))
  }
  # print(score.x)
  # print(score.z)
  xnew <- x
  xnew[,!keep.x] <- 0
  znew <- z
  znew[,!keep.z] <- 0
  return(list(x=xnew,z=znew, xscore=score.x, zscore=score.z))
}

varr <- function(x, meanx=NULL){
    n <- ncol(x)
      p <- nrow(x)
      Y <-matrix(1,nrow=n,ncol=1)
      if(is.null(meanx)){   meanx <- rowMeans(x)}
      ans<- rep(1, p)
      xdif <- x - meanx %*% t(Y)
      ans <- (xdif^2) %*% rep(1/(n - 1), n)
      ans <- drop(ans)
      return(ans)

  }

quantitative.func  <- function(x,y,s0=0){

    # regression of x on y

    my=mean(y)
      yy <- y-my
      temp <- x%*%yy
    mx=rowMeans(x)
    syy= sum(yy^2)

      scor <- temp/syy
      b0hat <- mx-scor*my
    ym=matrix(y,nrow=nrow(x),ncol=ncol(x),byrow=T)
      xhat <- matrix(b0hat,nrow=nrow(x),ncol=ncol(x))+ym*matrix(scor,nrow=nrow(x),ncol=ncol(x))
      sigma <- sqrt(rowSums((x-xhat)^2)/(ncol(xhat)-2))
      sd <- sigma/sqrt(syy)
      tt <- scor/(sd+s0)

      return(list(tt=tt, numer=scor, sd=sd))

  }

multiclass.func <- function(x,y,s0=0){

  ##assumes y is coded 1,2...

  nn <- table(y)
  m <- matrix(0,nrow=nrow(x),ncol=length(nn))
  v <- m
  for(j in 1:length(nn)){
    m[,j] <- rowMeans(x[,y==j])
    v[,j] <- (nn[j]-1)*varr(x[,y==j], meanx=m[,j])
  }
  mbar <- rowMeans(x)
  mm <- m-matrix(mbar,nrow=length(mbar),ncol=length(nn))
  fac <- (sum(nn)/prod(nn))
  scor <- sqrt(fac*(apply(matrix(nn,nrow=nrow(m),ncol=ncol(m),byrow=TRUE)*mm*mm,1,sum)))

  sd <- sqrt(rowSums(v)*(1/sum(nn-1))*sum(1/nn))
  tt <- scor/(sd+s0)
  mm.stand=t(scale(t(mm),center=FALSE,scale=sd))
  return(list(tt=tt, numer=scor, sd=sd,stand.contrasts=mm.stand))

}

