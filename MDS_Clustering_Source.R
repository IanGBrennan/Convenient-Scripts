# This function selects the best number of clusters according to the following criterion: 
# If there is a significant decline in gap from one cluster to two, then there is a single cluster; 
# otherwise, the largest increase in gap leads to the optimum number of clusters.

gapCR <- function(gaps, SEs){
  
  if(gaps[1] > (gaps[2] + SEs[2])){
    optimgap <- 1
  } else {
    if(any(gaps == Inf)){
      gaps <- gaps[1:(which(gaps == Inf)[1] - 1)]
      SEs <- SEs[1:length(gaps)]
    }
    gapdiffs <- sapply(1:(length(gaps)-1), function(i) gaps[i+1] - gaps[i])
    optimgap <- which(gapdiffs == max(gapdiffs)) + 1
    if((gaps[(optimgap - 1)] + SEs[(optimgap - 1)]) > gaps[optimgap]){
      print("The biggest difference in gaps is not significant! Returning NA.")
      return(NA)
    }
  }
  return(optimgap)
}

# This function receives a list of gene trees. It estimates the topological distance matrix. 
# MDS is then used for the given number of dimesion values and the given number of ks for each. 
# The output is a data matrix and a plot of how many dimensions were supported by each of the number 
# of dimensions.

require(cluster)
require(ape)

topclustMDS <- function(trs, mdsdim = 2, max.k, makeplot = T, criterion = "cr2", trdist = "topo"){
  
  # Create matrix of pairwise topological distances among trees
  
  topdistmat <- matrix(NA, ncol = length(trs), nrow = length(trs))
  for(i in 1:length(trs)){
    for(j in i:length(trs)){
      topdistmat[j, i] <- dist.topo(trs[[i]], trs[[j]], method = if(trdist == "topo") "PH85" else "score")
    }
    print(paste("finished column", i))
  }
  
  # Perform MDS representation of tree space
  
  mdsres <- cmdscale(as.dist(topdistmat), eig = T, k = mdsdim)
  if(makeplot) plot(mdsres$points)
  
  # Calculate gap statistcs for each number of clusters
  
  gapstats <- clusGap(mdsres$points, pam, max.k)
  gapstable <- gapstats$Tab
  gapstable[is.infinite(gapstable)] <- NA
  
  # The following section identifies the best-fitting number of clusters and the performs clustering usin the PAM function
  
  if(criterion == "max"){
    bestNclust <- which(gapstable[, "gap"] == max(gapstable[, "gap"], na.rm = T))
    if(length(bestNclust) > 1) bestNclust <- bestNclust[1]
  } else if(criterion == "cr2"){
    bestNclust <- gapCR(gapstable[,3], gapstable[,4])
  }
  
  clusterdata <- pam(mdsres$points, k = bestNclust)
  
  res <- list(topodists = topdistmat, mds = mdsres, gapstats = gapstats, loci = names(data), clustering.data = clusterdata, k = bestNclust)
  
  return(res)
  
}

# Stripped-down version of the clustMDS function. This just gives a pairwise comparison of all the trees
# Using Robinson-Foulds distances. This will give you a matrix of all pairwise RFs, as well as a table.

pairwise.RF <- function(input.trees, measure=c("PH85", "score")){
  topdistmat <- matrix(NA, ncol = length(input.trees), nrow = length(input.trees))
  RFtable <- NULL
  for(i in 1:length(input.trees)){
    for(j in i:length(input.trees)){
      topdistmat[j, i] <- dist.topo(input.trees[[i]], input.trees[[j]], method = measure)
      RFtable <- rbind(RFtable, data.frame(tree1=i, tree2=j, RFdist=topdistmat[j,i], 
                                           AGEdist=abs(max(nodeHeights(input.trees[[i]])) - max(nodeHeights(input.trees[[j]])))))
    }
    print(paste("finished column", i))
  }
  topdistmat <- as.data.frame(topdistmat)
  colnames(topdistmat) <- rownames(topdistmat)
  return(list(matrix=topdistmat, table=RFtable))
}




