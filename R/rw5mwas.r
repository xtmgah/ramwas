# test a phenotype against the data
# accounting for covariates
# cvrtqr - must be orthonormalized
# Supports categorical outcomes (text of factor)
testPhenotype = function(phenotype, data, cvrtqr){
    mycov = matrix(phenotype, nrow = 1);
    slice = data;
    cvqr0 = cvrtqr;

    if( any(is.na(mycov)) ){
        keep = which(colSums(is.na(mycov))==0);

        mycov = mycov[, keep, drop=FALSE];
        slice = slice[keep, , drop=FALSE];
        cvqr0 = cvqr0[, keep, drop=FALSE];
        cvqr0 = t( qr.Q(qr(t(cvqr0))) );
    }

    # mycov = as.character(round(mycov));
    if( is.character(mycov) || is.factor(mycov) ){
        fctr = as.factor(mycov);
        if(length(levels(fctr)) <= 1){
            return( list(Rsquared = 0,
                Fstat = 0,
                pvalue = 1,
                nVarTested = 0,
                dfFull = ncol(cvqr0) - nrow(cvqr0),
                statname = paste0("-F_",0)) );
        }
        dummy = t(model.matrix(~fctr)[,-1]);
        dummy = dummy - tcrossprod(dummy,cvqr0) %*% cvqr0;

        q = qr(t(dummy));
        keep = abs(diag(qr.R(q))) > .Machine$double.eps*ncol(mycov);

        mycov = t( qr.Q(qr(t(dummy))) );
        mycov[!keep,] = 0;
    } else {
        cvsumsq1 = sum( mycov^2 );
        mycov = mycov - tcrossprod(mycov,cvqr0) %*% cvqr0;
        cvsumsq2 = sum( mycov^2 );
        if( cvsumsq2 <= cvsumsq1 * .Machine$double.eps*ncol(mycov) ){
            mycov[] = 0;
        } else {
            mycov = mycov / sqrt(rowSums(mycov^2));
        }
    }

    ###
    nVarTested = nrow(mycov);
    dfFull = ncol(cvqr0) - nrow(cvqr0) - nVarTested;
    if(nVarTested == 1){
        if(dfFull <= 0)
            return(list(correlation = 0,
                        tstat = 0,
                        pvalue = 1,
                        nVarTested = nVarTested,
                        dfFull = dfFull,
                        statname = ""));

        # SST = rowSums(slice^2);
        SST = colSumsSq(slice);

        cvD = (mycov %*% slice);
        # cvD2 = colSums(cvD^2);
        # cvD2 = cvD2^2;

        cvC = (cvqr0 %*% slice);
        cvC2 = colSumsSq( cvC );
        # cvC2 = colSums( cvC^2 );

        # SSR = colSums( cvD^2 );
        cr = cvD / sqrt(pmax(SST - cvC2, 1e-50, SST/1e15));

        cor2tt = function(x){
            return( x * sqrt( dfFull / (1 - pmin(x^2,1))));
        }
        tt2pv = function(x){
            return( (pt(-abs(x),dfFull)*2));
        }
        tt = cor2tt(cr);
        pv = tt2pv(tt);

        ### Check:
        # c(tt[1], pv[1])
        # summary(lm( as.vector(covariate) ~ 0 + data[1,] +
        #         t(cvrtqr)))$coefficients[1,]
        return( list(correlation = cr,
                     tstat = tt,
                     pvalue = pv,
                     nVarTested = nVarTested,
                     dfFull = dfFull,
                     statname = "") );

    } else {
        if(dfFull <= 0)
            return( list(Rsquared = 0,
                         Fstat = 0,
                         pvalue = 1,
                         nVarTested = nVarTested,
                         dfFull = dfFull,
                         statname = paste0("-F_",nVarTested)) );

        # SST = rowSums(slice^2);
        SST = colSumsSq(slice);

        cvD = (mycov %*% slice);
        # cvD2 = colSums(cvD^2);
        cvD2 = colSumsSq(cvD);

        cvC = (cvqr0 %*% slice);
        # cvC2 = colSums( cvC^2 );
        cvC2 = colSumsSq( cvC );

        # SSR = colSums( cvD^2 );
        rsq = cvD2 / pmax(SST - cvC2, (SST+1e-16)/1e16);

        # rsq = colSums(cr^2);
        rsq2F = function(x){
            return( x / (1 - pmin(x,1)) * (dfFull/nVarTested) );
        }
        F2pv = function(x){
            return( pf(x, nVarTested, dfFull, lower.tail = FALSE) );
        }
        ff = rsq2F(rsq);
        pv = F2pv(ff);

        ### Check:
        # c(ff[1], pv[1])
        # anova(lm( data[1,] ~ 0 + t(cvrtqr) +
        #     as.factor(as.vector(as.character(round(covariate))))))
        return( list(Rsquared = rsq,
                     Fstat = ff,
                     pvalue = pv,
                     nVarTested = nVarTested,
                     dfFull = dfFull,
                     statname = paste0("-F_",nVarTested)) );
    }
}

# Fast QQ-plot
# With confidence band and lambda
# Makes small PDFs even with billions of p-values
qqPlotFast = function(pvalues, ntests=NULL, ci.level=0.05){

    if(is.null(ntests))
        ntests = length(pvalues);

    if(is.unsorted(pvalues))
        pvalues = sort.int(pvalues);

    ypvs = -log10(pvalues);
    xpvs = -log10(seq_along(ypvs) / ntests);

    if(length(ypvs) > 1000){
        # need to filter a bit, make the plotting faster
        levels = as.integer( (xpvs - xpvs[1])/(tail(xpvs,1) - xpvs[1]) * 2000);
        keep = c(TRUE, diff(levels)!=0);
        levels = as.integer( (ypvs - ypvs[1])/(tail(ypvs,1) - ypvs[1]) * 2000);
        keep = keep | c(TRUE, diff(levels)!=0);
        keep = which(keep);
        ypvs = ypvs[keep];
        xpvs = xpvs[keep];
        #         rm(keep)
    } else {
        keep = seq_along(ypvs)
    }
    mx = head(xpvs,1)*1.05;
    my = max(mx*1.15,head(ypvs,1))*1.05;
    plot(NA,NA, ylim = c(0,my), xlim = c(0,mx), xaxs="i", yaxs="i",
          xlab = expression("- log"[10]*"(p-value), expected under null"),
          ylab = expression("- log"[10]*"(p-value), observed"));
    # xlab = "-Log10(p-value), expected under null",
    # ylab = "-Log10(p-value), observed");
    lines(c(0,mx),c(0,mx),col="grey")
    points(xpvs, ypvs, col = "red", pch = 19, cex = 0.25);

    if(!is.null(ci.level)){
        if((ci.level>0)&(ci.level<1)){
            quantiles = qbeta(p = rep(c(ci.level/2,1-ci.level/2),
                                      each=length(xpvs)),
                              shape1 = keep,
                              shape2 = ntests - keep + 1);
            quantiles = matrix(quantiles, ncol=2);

            lines( xpvs, -log10(quantiles[,1]), col="cyan4")
            lines( xpvs, -log10(quantiles[,2]), col="cyan4")
        }
    }
    legend("bottomright",
           c("P-values", sprintf("%.0f %% Confidence band",100-ci.level*100)),
           lwd = c(0,1),
           pch = c(19,NA_integer_),
           lty = c(0,1),
           col=c("red","cyan4"))
    if(length(pvalues)*2>ntests){
        lambda = sprintf("%.3f",
                         qchisq(pvalues[ntests/2],1,lower.tail = FALSE) /
                         qchisq(0.5,1,lower.tail = FALSE));
        legend("bottom", legend = bquote(lambda == .(lambda)), bty = "n")
        #         text(mx, mx/2, bquote(lambda == .(lambda)), pos=2)
    }
    return(invisible(NULL));
}


# Save top findings in a text file
# with annotation
ramwas5saveTopFindings = function(param){
    # library(filematrix)
    param = parameterPreprocess(param);

    message("Working in: ", param$dirmwas);

    message("Loading MWAS results");
    mwas = fm.load( paste0(param$dirmwas, "/Stats_and_pvalues") );

    message("Loading CpG locations");
    cpgloc = fm.load(
        filenamebase = paste0(param$dircoveragenorm, "/CpG_locations") );
    chrnames = readLines(
        con = paste0(param$dircoveragenorm, "/CpG_chromosome_names.txt") );

    message("Finding top MWAS hits");
    keep = findBestNpvs(mwas[,3], param$toppvthreshold);
    # keep = which(mwas[,3] < param$toppvthreshold);
    ord = keep[sort.list(abs(mwas[keep,2]),decreasing = TRUE)];

    toptable = data.frame( chr = chrnames[cpgloc[ord,1]],
                                  position =     cpgloc[ord,2],
                                  tstat  = mwas[ord,2],
                                  pvalue = mwas[ord,3],
                                  qvalue = mwas[ord,4]);

    # saveRDS(file = paste0(param$dirmwas,"/Top_tests.rds"), object = toptable);


    message("Saving top MWAS hits");
    write.table(
        file = paste0(param$dirmwas,"/Top_tests.txt"),
        sep = "\t", quote = FALSE, row.names = FALSE,
        x = toptable
    );
    return(invisible(NULL));
}

# Job function for MWAS
.ramwas5MWASjob = function(rng, param){
    # rng = rangeset[[1]];
    # library(filematrix);
    .set1MLKthread();
    ld = param$dirmwas;
  
    .log(ld, "%s, Process %06d, Job %02d, Start MWAS, CpG range %d-%d",
        date(), Sys.getpid(), rng[3], rng[1], rng[2]);
  
    # Get data access
    data = new("rwDataClass");
    data$open(param, lockfile = param$lockfile2);

    outmat = double(3*(rng[2]-rng[1]+1));
    dim(outmat) = c((rng[2]-rng[1]+1),3);

    step1 = ceiling( 128*1024*1024 / data$ndatarows / 8);
    mm = rng[2]-rng[1]+1;
    nsteps = ceiling(mm/step1);
    for( part in seq_len(nsteps) ){ # part = 1
        .log(ld, "%s, Process %06d, Job %02d, Processing slice: %03d of %d",
            date(), Sys.getpid(), rng[3], part, nsteps);
        fr = (part-1)*step1 + rng[1];
        to = min(part*step1, mm) + rng[1] - 1;

        slice = data$getDataRez(fr:to, resid = FALSE);
        
        rez = testPhenotype(
                    phenotype = param$covariates[[param$modeloutcome]],
                    data = slice,
                    cvrtqr = t(data$cvrtqr))

        outmat[(fr:to) - (rng[1] - 1), ] = cbind(rez[[1]], rez[[2]], rez[[3]]);

        rm(slice);
    }
    data$close();

    if( rng[1] == 1 ){
        writeLines( 
                con = paste0(param$dirmwas, "/DegreesOfFreedom.txt"),
                text = as.character(c(rez$nVarTested, rez$dfFull)));
    }

    fmout = fm.open(
                filenamebase = paste0(param$dirmwas, "/Stats_and_pvalues"),
                lockfile = param$lockfile2);
    fmout[rng[1]:rng[2], 1:3] = outmat;
    close(fmout);
    .log(ld, "%s, Process %06d, Job %02d, Done MWAS, CpG range %d-%d",
        date(), Sys.getpid(), rng[3], rng[1], rng[2]);

    return(invisible(NULL));
}

# Setp 5 of RaMWAS
ramwas5MWAS = function( param ){
    # library(filematrix)
    param = parameterPreprocess(param);
    ld = param$dirmwas;
    dir.create(param$dirmwas, showWarnings = FALSE, recursive = TRUE);
     .log(ld, "%s, Start ramwas5MWAS() call", date(), append = FALSE);

    if(is.null(param$modeloutcome))
        stop("Model outcome variable not defined\n",
             "See \"modeloutcome\" parameter");
    if( !any(names(param$covariates) == param$modeloutcome) )
        stop("Model outcome is not found among covariates.\'n",
             "See \"modeloutcome\" parameter");
    
    parameterDump(dir = param$dirmwas, param = param,
        toplines = c(   "dirmwas", "dirpca", "dircoveragenorm",
                        "filecovariates", "covariates",
                        "modeloutcome", "modelcovariates",
                        "modelPCs", "modelhasconstant",
                        "qqplottitle",
                        "diskthreads"));


    ### Kill NA outcomes
    killset = is.na(param$covariates[[ param$modeloutcome ]]);
    if(any(killset)){
        .log(ld, "%s, Removing observations with missing outcome", date());
        param$covariates = data.frame(lapply(
            param$covariates,
            `[`,
            !killset), stringsAsFactors = FALSE);
    }
    
    outcome = param$covariates[[ param$modeloutcome ]];
    
    # Get data access
    data = new("rwDataClass");
    data$open(param);

    ### Outpout matrix. Cor / t-test / p-value / q-value
    ### Outpout matrix. R2  / F-test / p-value / q-value
    {
        .log(ld, "%s, Creating output matrix", date());
        fm = fm.create( 
                    filenamebase = paste0(param$dirmwas, "/Stats_and_pvalues"),
                    nrow = data$ncpgs,
                    ncol = 4);
        if( is.numeric( outcome ) ){
            colnames(fm) = c("cor","t-test","p-value","q-value");
        } else {
            colnames(fm) = c("R-squared","F-test","p-value","q-value");
        }
        close(fm);
    }

    ### Running MWAS in parallel
    {
        .log(ld, "%s, Start Association Analysis", date());

        step1 = ceiling( 128*1024*1024 / data$ndatarows / 8);
        mm = data$ncpgs;
        nsteps = ceiling(mm/step1);

        nthreads = min(param$cputhreads, nsteps);
        rm(step1, mm, nsteps);
        if( nthreads > 1 ){
            rng = round(seq(1, data$ncpgs+1, length.out = nthreads+1));
            rangeset = rbind( 
                            rng[-length(rng)],
                            rng[-1] - 1,
                            seq_len(nthreads));
            rangeset = mat2cols(rangeset);

            if(param$usefilelock) param$lockfile2 = tempfile();
            # library(parallel);
            cl = makeCluster(nthreads);
            on.exit({
                stopCluster(cl);
                .file.remove(param$lockfile2);
            });
            clusterExport(cl, "testPhenotype");
            logfun = .logErrors(ld, .ramwas3coverageJob);
            z = clusterApplyLB(
                        cl = cl,
                        x = rangeset,
                        fun = logfun,
                        param = param);
            .showErrors(z);
            tmp = sys.on.exit();
            eval(tmp);
            rm(tmp);
            on.exit();
            rm(cl, rng, rangeset);

        } else {
            z = .ramwas5MWASjob(
                        rng = c(1, data$ncpgs, 0),
                        param = param);
        }
        
        .log(ld, "%s, Done Association Analysis", date());
    }
    data$close();

    ### Fill in FDR column
    {
        .log(ld, "%s, Calculating FDR (q-values)", date());
        message("Calculating FDR (q-values)");
        fm = fm.open(paste0(param$dirmwas, "/Stats_and_pvalues"));
        pvalues = fm[,3];
        pvalues[pvalues==0] = .Machine$double.xmin;
        fm[,4] = pvalue2qvalue( pvalues );
        close(fm);
    } # sortedpv

    ### QQ-plot
    {
        message("Creating QQ-plot");
        pdf(paste0(param$dirmwas, "/QQ_plot.pdf"), 7, 7);
        qqPlotFast(pvalues);
        title(param$qqplottitle);
        dev.off();
    }
    ramwas5saveTopFindings(param);
    return(invisible(NULL));
}
