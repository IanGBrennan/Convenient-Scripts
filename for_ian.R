library(raster)
library(metricTester)
library(picante)
library(fields)
library(tibble); library(dplyr)

#i edited this function a while ago i can';'t remeber why but you should use it
# make sure you source it after loading metricTester library
source("/Users/Ian/Google.Drive/R.Analyses/Convenient Scripts/edited_dispersalNull_function_metrictester.R")

#load your community matrix

#cm <- community.matrix
cm <- gridded.dist

# so to get site x site distance matrix you'll need the lat/lons
# so you call this function using the raster you built your cm with
# you can subset it by cells (so only the ones you have in your cm) or just get all of them and subset it later
# cells in a raster are labelled chronologically from the top left to bottom right
# so if you make a species richness raster

#richness.raster <- your.original.raster
richness.raster <- rr; richness.raster@data@values[] <- 0
fd.raster <- rr; fd.raster@data@values[] <- 0
ses.raster <- rr; ses.raster@data@values[] <- 0

pre.rr <- left_join(rr.cells, cm, by=c("latitude", "longitude")); pre.rr[is.na(pre.rr)] <- 0
pre.fd <- left_join(rr.cells, res.table, by=c("latitude", "longitude"))
    pre.fd <- left_join(pre.fd, cm, by=c("latitude", "longitude")); pre.fd[is.na(pre.fd)] <- 0

    
#richness.raster@data@values <- rowsums(cm)
richness.raster@data@values <- pre.rr$richness
fd.raster@data@values <- pre.fd$RaoQ

#check it makes sense
plot(richness.raster)
plot(fd.raster)

# you can find cell number you want to use
cells.rich <- which(richness.raster@data@values > 1)
cells.fd <- which(fd.raster@data@values > 0)

# make your input files
input.rr <- pre.rr[,4:ncol(pre.rr)]; input.rr <- input.rr[which(rowSums(input.rr) > 1),]
input.fd <- pre.fd[which(pre.fd$RaoQ > 0), 5:ncol(pre.fd)]

#then get coords of those cells
coords.rich <- xyFromCell(richness.raster, cells.rich)
coords.fd <- xyFromCell(fd.raster, cells.fd)

# this will give you the great circle distance which is in meters
#gc.dist <- rdist.earth(coords)
gc.dist.rich <- rdist.earth(coords.rich); rownames(gc.dist.rich) <- cells.rich; colnames(gc.dist.rich) <- cells.rich; diag(gc.dist.rich) <- 0
gc.dist.fd <- rdist.earth(coords.fd); rownames(gc.dist.fd) <- cells.fd; colnames(gc.dist.fd) <- cells.fd; diag(gc.dist.fd) <- 0


#this should give you matrix that has the same row/col length as the number of sites in your cm

# running this can take some time dependning on your resolution
# will need to loop it to get a distribution of cms

#cdm_simulated <- DNM(cm, tree = NA, gc.dist, abundance.matters = F)
#cdm_simulated <- DNM(input.rr, tree=NA, gc.dist.rich, abundance.matters=F, abundance.assigned="explore")
cdm_simulated <- DNM(input.test, tree=NA, gc.dist.test,   abundance.matters=F, abundance.assigned="directly")

# we can test this by shortening the data:
#input.test <- input.fd[1:100,1:50]
#gc.dist.test <- gc.dist.fd[1:100,1:100]

#### Instead of just running the null model once, run it a bunch with this function
# need to pull out 'trait.frame' and 'input.fd', 'gc.dist.fd'
nullFD <- function(n.model, n.iter, method=c("randomizeMatrix", "DNM"), cores){
  beginning <- Sys.time()
  Rao.table <- NULL
  
  if(method=="randomizeMatrix"){
    swap <- mclapply(1:n.iter, function(x) {randomizeMatrix(input.fd, null.model=n.model, iterations=10)}, mc.cores=cores)
    swap.res <- mclapply(1:length(swap), function(x) {dbFD(trait.frame, swap[[x]])}, mc.cores=8)
    
    for(j in 1:length(swap.res)){
      Rao.table <- cbind(Rao.table, swap.res[[j]]$RaoQ)
    }
  }
  else if(method=="DNM"){
    swap <- mclapply(1:n.iter, function(x) {DNM(input.fd, tree=NA, gc.dist.fd,   abundance.matters=F, abundance.assigned="directly")}, mc.cores=cores)
    swap.res <- mclapply(1:length(swap), function(x) {dbFD(trait.frame, swap[[x]])}, mc.cores=8)
    
    for(j in 1:length(swap.res)){
      Rao.table <- cbind(Rao.table, swap.res[[j]]$RaoQ)
    }
  }
  
  end <- Sys.time()
  duration <- format(end-beginning)
  print(paste("Computation time to fit", n.iter, method, "null models:", duration))
  
  Rao.table <- as.data.frame(Rao.table); Raw.table <- Rao.table
  Rao.table <- cbind(Rao.table, sim.mean=rowMeans(Rao.table))
  Rao.table <- cbind(Rao.table, sim.sd=apply(Raw.table, 1, sd))
  #Rao.table <- cbind(Rao.table, emp.val=) # I could add in the empirical values (FD)
  #Rao.table <- cbind(Rao.table, ses=apply(Rao.table, 1, (Rao.table[,"mean"]))) # then I could calculate the SES straight away
  return(Rao.table)
}
RQ <- nullFD(n.model=NULL, n.iter=10, method="DNM", cores=4)
RQ <- nullFD(n.model="independentswap", n.iter=10, method="randomizeMatrix", cores=8)
#RO <- RQ
RQ <- cbind(RQ, emp.val=res.table$RaoQ)
apply(RQ, 1, function(x) {((RQ[x,"emp.val"] - RQ[x,"sim.mean"])/RQ[x,"sim.sd"])})
apply(RQ, 1, function(x) (RQ$emp.val - RQ$sim.mean)/RQ$sim.sd)

ses.vec <- NULL
for(k in 1:nrow(RQ)){
  curr <- RQ[k,]
  ses <- (curr$emp.val - curr$sim.mean) / curr$sim.sd
  ses.vec <- append(ses.vec, ses)
}
RQ <- cbind(RQ, ses=ses.vec)

ses.table <- cbind.data.frame(latitude=gridded.dist$latitude, longitude=gridded.dist$longitude, SES=RQ$ses)

ses.fd <- left_join(rr.cells, ses.table, by=c("latitude", "longitude"))
ses.fd <- left_join(ses.fd, cm, by=c("latitude", "longitude")); ses.fd[is.na(ses.fd)] <- 0

ses.raster@data@values <- ses.fd$SES
plot(ses.raster)

densityplot(ses.raster@data@values)




RQ <- cbind(RQ)

mtcars %>% by_row(purrr::lift_vl(mean))
RQ %>% by_row((emp.val - sim.mean)/sim.sd)

Rao.table <- NULL
for (i in 1:10){
  swap <- DNM(input.fd, tree=NA, gc.dist.fd,   abundance.matters=F, abundance.assigned="directly")
  #swap.res <- dbFD(trait.frame, swap)
  #Rao.table <- cbind(Rao.table, swap.res$RaoQ)
}

# Take the simulated distributions and get FD from the matrix
#FD.sim <- dbFD(trait.frame, cdm_simulated) # use goanna.frame or trait.frame
#FD.sim <- dbFD(trait.frame, cdm_inswap)
#sim.table <- cbind.data.frame(latitude=gridded.dist$latitude, longitude=gridded.dist$longitude, RaoQ=FD.sim$RaoQ)
sim.table <- cbind.data.frame(latitude=gridded.dist$latitude, longitude=gridded.dist$longitude, RaoQ=RQ$mean)

sim.fd <- left_join(rr.cells, sim.table, by=c("latitude", "longitude"))
    sim.fd <- left_join(sim.fd, cm, by=c("latitude", "longitude")); sim.fd[is.na(sim.fd)] <- 0

sim.raster@data@values <- sim.fd$RaoQ
plot(sim.raster)

diff.raster <- fd.raster
diff.raster@data@values <- as.vector(fd.raster@data@values) - as.vector(sim.raster@data@values)
#diff.raster@data@values <- as.vector(sim.raster@data@values) - as.vector(fd.raster@data@values)
#diff.raster@data@values[is.na(diff.raster@data@values)] <- 0
plot(diff.raster)

emp.fd <- fd.raster@data@values[fd.raster@data@values > 0]
densityplot(emp.fd)
sim.df <- sim.raster@data@values[sim.raster@data@values > 0]
densityplot(sim.df)
stats::var(emp.fd); mean(emp.fd); stats::var(sim.df); mean(sim.df)

#cdm_simulated <- DNM(gridded.dist[,4:ncol(gridded.dist)], tree=NA, gc.dist, abundance.matters=F)

# read the simulated data as a DF
cm.sim <- as.data.frame(cdm_simulated)
# read in the raster, make all values 0
sim.raster <- rr; sim.raster@data@values[] <- 0
# calculate the richness using rowSums
cm.sim <- cbind(cm.sim, rowSums(cm.sim)); colnames(cm.sim)[ncol(cm.sim)] <- "richness"
# combine the simulated results with the blank raster cells
cm.simmer <- left_join(rownames_to_column(rr.cells), rownames_to_column(cm.sim), by = "rowname")
# put the values into the raster
sim.raster@data@values <- cm.simmer[,"richness"]; sim.raster@data@values[is.na(sim.raster@data@values)] <- 0
# plot the simulated richness
plot(sim.raster); # plot(fd.raster)

diff.raster <- richness.raster
diff.raster@data@values <- as.vector(fd.raster@data@values) - as.vector(sim.raster@data@values)
#diff.raster@data@values <- as.vector(sim.raster@data@values) - as.vector(fd.raster@data@values)
#diff.raster@data@values[is.na(diff.raster@data@values)] <- 0
plot(diff.raster)


cdm1 <- cdm_simulated
cdm2 <- cdm_simulated
cdm3 <- cdm_simulated




cdm_inswap <- randomizeMatrix(input.fd, null.model="trialswap", iterations=1000)







res.list <- mclapply(1:n.iter, function(x) {
  fitTipData(model, traits, GLSstyle=T, params0 = init.params[[x]])}, mc.cores = n.proc)

swap <- mclapply(1:100, function(x) {randomizeMatrix(input.fd, null.model="independentswap", iterations=1)}, mc.cores=8)
