# Multinomial model
eNetXplorerMultinomial <- function(x, y, family, alpha, nlambda, nlambda.ext, seed, scaled,
n_fold, n_run, n_perm_null, save_lambda_QF_full, QF.FUN, QF_label, multinom_method, fscore_beta, fold_distrib_fail.max,...)
{
    n_instance = nrow(x)
    n_feature = ncol(x)
    instance = rownames(x)
    if (is.null(instance)) {
        instance = paste0("Inst.",1:nrow(x))
    }
    feature = colnames(x)
    if (is.null(feature)) {
        feature = paste0("Feat.",1:ncol(x))
    }
    
    if (!is.null(dim(y))&&(ncol(y)>1)) {
        stop("Response must be a factor\n")
    }
    y <- as.factor(y) # to force y into a factor
    class = levels(y)
    n_class = length(class)
    
    prediction_type = "class"
    
    if (is.null(QF.FUN)) {
        QF_label = multinom_method
        if (QF_label=="avg accuracy") {
            QF = function(predicted,response) {
                avg_acc = 0
                for (i_class in 1:n_class) {
                    avg_acc = avg_acc + sum((response==class[i_class])==(predicted==class[i_class]))
                }
                return (avg_acc/(n_class*n_instance))
            }
        } else if (QF_label=="avg precision") {
            QF = function(predicted,response) {
                precision = 0
                for (i_class in 1:n_class) {
                    precision = precision + sum((response==class[i_class])&(predicted==class[i_class]))/sum(predicted==class[i_class])
                }
                return (precision/n_class)
            }
        } else if (QF_label=="avg recall") {
            QF = function(predicted,response) {
                recall = 0
                for (i_class in 1:n_class) {
                    recall = recall + sum((response==class[i_class])&(predicted==class[i_class]))/sum(response==class[i_class])
                }
                return (recall/n_class)
            }
        } else if (QF_label=="avg Fscore") {
            if (is.null(fscore_beta)) {
                fscore_beta=1
            }
            QF = function(predicted,response) {
                precision = 0
                recall = 0
                for (i_class in 1:n_class) {
                    tresp = response==class[i_class]
                    tpred = predicted==class[i_class]
                    num = sum(tresp&tpred)
                    precision = precision + num/sum(tpred)
                    recall = recall + num/sum(tresp)
                }
                return ((fscore_beta**2+1)*precision*recall/(fscore_beta**2*precision+recall)/n_class)
            }
        }
    } else {
        QF = QF.FUN
        if (is.null(QF_label)) {
            QF_label = "user-provided"
        }
    }
    
    if (!is.null(seed)) {
        set.seed(seed) # set the seed for reproducibility
    }
    
    if (scaled) { # data are z-score transformed
        x_col_mean = apply(x,2,mean)
        x_col_sd = apply(x,2,sd)
        for (i in 1:ncol(x)) {
            x[,i] = (x[,i]-x_col_mean[i])/x_col_sd[i]
        }
    }
    
    foldid = NULL # we determine the fold template
    fold_size = floor(n_instance/n_fold)
    for (i_fold in 1:n_fold) {
        foldid = c(foldid,rep(i_fold,fold_size))
    }
    fold_rest = n_instance%%n_fold
    if (fold_rest>0) {
        for (i_fold in 1:fold_rest) {
            foldid = c(foldid,i_fold)
        }
    }
    
    n_alpha = length(alpha)
    n_alpha_eff = 0
    best_lambda = rep(NA,n_alpha)
    model_QF_est = rep(NA,n_alpha)
    
    lambda_values = vector("list",n_alpha)
    lambda_QF_est = vector("list",n_alpha)
    lambda_QF_est_full = vector("list",n_alpha)
    
    foldid_per_run = vector("list",n_alpha)
    predicted_values = vector("list",n_alpha)
    
    feature_coef_wmean = vector("list",n_class)
    feature_coef_wsd = vector("list",n_class)
    feature_freq_mean = vector("list",n_class)
    feature_freq_sd = vector("list",n_class)
    for (i_class in 1:n_class) {
        feature_coef_wmean[[i_class]] = matrix(rep(NA,n_feature*n_alpha),ncol=n_alpha)
        feature_coef_wsd[[i_class]] = matrix(rep(NA,n_feature*n_alpha),ncol=n_alpha)
        feature_freq_mean[[i_class]] = matrix(rep(NA,n_feature*n_alpha),ncol=n_alpha)
        feature_freq_sd[[i_class]] = matrix(rep(NA,n_feature*n_alpha),ncol=n_alpha)
    }
    null_feature_coef_wmean = vector("list",n_class)
    null_feature_coef_wsd = vector("list",n_class)
    null_feature_freq_mean = vector("list",n_class)
    null_feature_freq_sd = vector("list",n_class)
    for (i_class in 1:n_class) {
        null_feature_coef_wmean[[i_class]] = matrix(rep(NA,n_feature*n_alpha),ncol=n_alpha)
        null_feature_coef_wsd[[i_class]] = matrix(rep(NA,n_feature*n_alpha),ncol=n_alpha)
        null_feature_freq_mean[[i_class]] = matrix(rep(NA,n_feature*n_alpha),ncol=n_alpha)
        null_feature_freq_sd[[i_class]] = matrix(rep(NA,n_feature*n_alpha),ncol=n_alpha)
    }
    
    QF_model_vs_null_pval = rep(NA,n_alpha)
    feature_coef_model_vs_null_pval =  vector("list",n_class)
    feature_freq_model_vs_null_pval =  vector("list",n_class)
    for (i_class in 1:n_class) {
        feature_coef_model_vs_null_pval[[i_class]] = matrix(rep(NA,n_feature*n_alpha),ncol=n_alpha)
        feature_freq_model_vs_null_pval[[i_class]] = matrix(rep(NA,n_feature*n_alpha),ncol=n_alpha)
    }
    
    glmnet.control(factory=T) # resets internal glmnet parameters
    glmnet.control(...) # to allow changes of factory default parameters in glmnet
    
    # return object
    return_obj <- function(n_alpha_eff) {
        rownames(x) = instance
        colnames(x) = feature
        names(y) = instance
        alpha_label = paste0("a",alpha[1:n_alpha_eff])
        best_lambda = best_lambda[1:n_alpha_eff]
        names(best_lambda) = alpha_label
        model_QF_est = model_QF_est[1:n_alpha_eff]
        names(model_QF_est) = alpha_label
        QF_model_vs_null_pval = QF_model_vs_null_pval[1:n_alpha_eff]
        names(QF_model_vs_null_pval) = alpha_label
        lambda_values = lambda_values[1:n_alpha_eff]
        names(lambda_values) = alpha_label
        lambda_QF_est = lambda_QF_est[1:n_alpha_eff]
        names(lambda_QF_est) = alpha_label
        lambda_QF_est_full = lambda_QF_est_full[1:n_alpha_eff]
        names(lambda_QF_est_full) = alpha_label
        predicted_values = predicted_values[1:n_alpha_eff]
        names(predicted_values) = alpha_label
        for (i_alpha in 1:n_alpha_eff) {
            colnames(predicted_values[[i_alpha]]) = class
            rownames(predicted_values[[i_alpha]]) = instance
        }
        names(feature_coef_wmean) = class
        names(feature_coef_wsd) = class
        names(feature_freq_mean) = class
        names(feature_freq_sd) = class
        names(null_feature_coef_wmean) = class
        names(null_feature_coef_wsd) = class
        names(null_feature_freq_mean) = class
        names(null_feature_freq_sd) = class
        names(feature_coef_model_vs_null_pval) = class
        names(feature_freq_model_vs_null_pval) = class
        # conversion from list of matrices to list of sparse matrices
        for (i_class in 1:n_class) {
            feature_coef_wmean[[i_class]] = as(feature_coef_wmean[[i_class]][,1:n_alpha_eff,drop=F],"CsparseMatrix")
            rownames(feature_coef_wmean[[i_class]]) = feature
            colnames(feature_coef_wmean[[i_class]]) = alpha_label
            feature_coef_wsd[[i_class]] = as(feature_coef_wsd[[i_class]][,1:n_alpha_eff,drop=F],"CsparseMatrix")
            rownames(feature_coef_wsd[[i_class]]) = feature
            colnames(feature_coef_wsd[[i_class]]) = alpha_label
            feature_freq_mean[[i_class]] = as(feature_freq_mean[[i_class]][,1:n_alpha_eff,drop=F],"CsparseMatrix")
            rownames(feature_freq_mean[[i_class]]) = feature
            colnames(feature_freq_mean[[i_class]]) = alpha_label
            feature_freq_sd[[i_class]] = as(feature_freq_sd[[i_class]][,1:n_alpha_eff,drop=F],"CsparseMatrix")
            rownames(feature_freq_sd[[i_class]]) = feature
            colnames(feature_freq_sd[[i_class]]) = alpha_label
            null_feature_coef_wmean[[i_class]] = as(null_feature_coef_wmean[[i_class]][,1:n_alpha_eff,drop=F],"CsparseMatrix")
            rownames(null_feature_coef_wmean[[i_class]]) = feature
            colnames(null_feature_coef_wmean[[i_class]]) = alpha_label
            null_feature_coef_wsd[[i_class]] = as(null_feature_coef_wsd[[i_class]][,1:n_alpha_eff,drop=F],"CsparseMatrix")
            rownames(null_feature_coef_wsd[[i_class]]) = feature
            colnames(null_feature_coef_wsd[[i_class]]) = alpha_label
            null_feature_freq_mean[[i_class]] = as(null_feature_freq_mean[[i_class]][,1:n_alpha_eff,drop=F],"CsparseMatrix")
            rownames(null_feature_freq_mean[[i_class]]) = feature
            colnames(null_feature_freq_mean[[i_class]]) = alpha_label
            null_feature_freq_sd[[i_class]] = as(null_feature_freq_sd[[i_class]][,1:n_alpha_eff,drop=F],"CsparseMatrix")
            rownames(null_feature_freq_sd[[i_class]]) = feature
            colnames(null_feature_freq_sd[[i_class]]) = alpha_label
            feature_coef_model_vs_null_pval[[i_class]] = as(feature_coef_model_vs_null_pval[[i_class]][,1:n_alpha_eff,drop=F],"CsparseMatrix")
            rownames(feature_coef_model_vs_null_pval[[i_class]]) = feature
            colnames(feature_coef_model_vs_null_pval[[i_class]]) = alpha_label
            feature_freq_model_vs_null_pval[[i_class]] = as(feature_freq_model_vs_null_pval[[i_class]][,1:n_alpha_eff,drop=F],"CsparseMatrix")
            rownames(feature_freq_model_vs_null_pval[[i_class]]) = feature
            colnames(feature_freq_model_vs_null_pval[[i_class]]) = alpha_label
        }
        list(
        # input data and parameters
        predictor = as(x,"CsparseMatrix"), response = y, alpha = alpha[1:n_alpha_eff], family = family, nlambda = nlambda,
        nlambda.ext = nlambda.ext, seed = seed, scaled = scaled, n_fold = n_fold, n_run = n_run,
        n_perm_null = n_perm_null, save_lambda_QF_full = save_lambda_QF_full,
        QF_label = QF_label, multinom_method = multinom_method,
        fscore_beta = fscore_beta, instance = instance, feature = feature,
        fold_distrib_fail.max = fold_distrib_fail.max, glmnet_params = glmnet.control(),
        # summary results
        best_lambda = best_lambda, model_QF_est = model_QF_est, QF_model_vs_null_pval = QF_model_vs_null_pval,
        # detailed results for plots and downstream analysis
        lambda_values = lambda_values, lambda_QF_est = lambda_QF_est, lambda_QF_est_full = lambda_QF_est_full,
        predicted_values = predicted_values,
        feature_coef_wmean = feature_coef_wmean, feature_coef_wsd = feature_coef_wsd,
        feature_freq_mean = feature_freq_mean, feature_freq_sd = feature_freq_sd,
        null_feature_coef_wmean = null_feature_coef_wmean, null_feature_coef_wsd = null_feature_coef_wsd,
        null_feature_freq_mean = null_feature_freq_mean, null_feature_freq_sd = null_feature_freq_sd,
        feature_coef_model_vs_null_pval = feature_coef_model_vs_null_pval,
        feature_freq_model_vs_null_pval = feature_freq_model_vs_null_pval
        )
    }

    tryCatch({
        for (i_alpha in 1:n_alpha) { # beginning of alpha loop
            fit = glmnet(x,y,alpha=alpha[i_alpha],family=family,nlambda=nlambda)
            # We extend the range of lambda values (if nlambda.ext is set)
            if (!is.null(nlambda.ext)&&nlambda.ext>nlambda) {
                lambda_max = fit$lambda[1]*sqrt(nlambda.ext/length(fit$lambda))
                lambda_min = fit$lambda[length(fit$lambda)]/sqrt(nlambda.ext/length(fit$lambda))
                lambda_values[[i_alpha]] = lambda_max*(lambda_min/lambda_max)**(((1:nlambda.ext)-1)/(nlambda.ext-1))
            } else {
                lambda_values[[i_alpha]] = fit$lambda
            }
            n_lambda = length(lambda_values[[i_alpha]])
            predicted_values_all_lambda = matrix(rep(NA,n_instance*n_run*n_lambda),ncol=n_lambda)
            feature_coef_per_lambda = vector("list",n_lambda)
            feature_freq_per_lambda = vector("list",n_lambda)
            for (i_lambda in 1:n_lambda) {
                feature_coef_per_lambda[[i_lambda]] = vector("list",n_class)
                feature_freq_per_lambda[[i_lambda]] = vector("list",n_class)
                for (i_class in 1:n_class) {
                    feature_coef_per_lambda[[i_lambda]][[i_class]] = matrix(rep(NA,n_feature*n_run),ncol=n_run)
                    feature_freq_per_lambda[[i_lambda]][[i_class]] = matrix(rep(NA,n_feature*n_run),ncol=n_run)
                }
            }
            foldid_per_run[[i_alpha]] = matrix(rep(NA,n_instance*n_run),ncol=n_run)
            pb <- progress_bar$new(
            format = paste0("  running MODEL for alpha = ",alpha[i_alpha]," [:bar] :percent in :elapsed"),
            total = n_run, clear = T, width= 60)
            for (i_run in 1:n_run) {
                fold_distrib_OK = F
                fold_distrib_fail = 0
                while (!fold_distrib_OK) { # for categorical models, we must check that each class is in more than 1 fold.
                    foldid_per_run[[i_alpha]][,i_run] = sample(foldid)
                    if (sum(apply(table(foldid_per_run[[i_alpha]][,i_run],y)>0,2,sum)>1)==n_class) {
                        fold_distrib_OK = T
                    } else {
                        fold_distrib_fail = fold_distrib_fail + 1
                        if (fold_distrib_fail>fold_distrib_fail.max) {
                            stop("Failure in class distribution across cross-validation folds. Increase n_fold, remove very small classes, or re-run with larger fold_distrib_fail.max\n")
                        }
                    }
                }
                feature_coef_per_run = vector("list",n_lambda)
                for (i_lambda in 1:n_lambda) {
                    feature_coef_per_run[[i_lambda]] = vector("list",n_class)
                    for (i_class in 1:n_class) {
                        feature_coef_per_run[[i_lambda]][[i_class]] = matrix(rep(NA,n_feature*n_fold),ncol=n_fold)
                    }
                }
                for (i_fold in 1:n_fold) {
                    instance_in_bag = foldid_per_run[[i_alpha]][,i_run]!=i_fold
                    fit = glmnet(x[instance_in_bag,],y[instance_in_bag],alpha=alpha[i_alpha],family=family,lambda=lambda_values[[i_alpha]])
                    n_lambda_eff = length(fit$lambda) # n_lambda_eff may be smaller than n_lambda
                    predicted_values_all_lambda[n_instance*(i_run-1)+which(!instance_in_bag),] = predict(fit, x[!instance_in_bag,], type=prediction_type)
                    for (i_lambda in 1:n_lambda_eff) {
                        for (i_class in 1:n_class) {
                            feature_coef_per_run[[i_lambda]][[i_class]][,i_fold] = coef(fit)[[i_class]][-1,][,i_lambda] # we remove the intercept
                        }
                    }
                }
                for (i_lambda in 1:n_lambda) {
                    for (i_class in 1:n_class) {
                        is.na(feature_coef_per_run[[i_lambda]][[i_class]]) <- feature_coef_per_run[[i_lambda]][[i_class]] == 0
                        feature_coef_per_lambda[[i_lambda]][[i_class]][,i_run] = rowMeans(feature_coef_per_run[[i_lambda]][[i_class]], na.rm=T) # we obtain the mean (nonzero) coefficients over folds.
                        feature_freq_per_lambda[[i_lambda]][[i_class]][,i_run] = rowSums(!is.na(feature_coef_per_run[[i_lambda]][[i_class]]))/n_fold
                    }
                }
                pb$tick()
            }
            pb <- progress_bar$new(
            format = paste0("  MODEL predictions for alpha = ",alpha[i_alpha]," [:bar] :percent in :elapsed"),
            total = n_lambda, clear = T, width= 60)
            lambda_QF_est_all_runs = matrix(rep(NA,n_lambda*n_run),ncol=n_run)
            for (i_lambda in 1:n_lambda) {
                for (i_run in 1:n_run) {
                    predicted_OOB = predicted_values_all_lambda[(1:n_instance)+(i_run-1)*n_instance,i_lambda]
                    if (sum(is.na(predicted_OOB))==0) {
                        lambda_QF_est_all_runs[i_lambda,i_run] = QF(predicted_OOB,y)
                    }
                }
                pb$tick()
            }
            if (save_lambda_QF_full) {
                lambda_QF_est_full[[i_alpha]] = lambda_QF_est_all_runs
            }
            lambda_QF_est[[i_alpha]] = apply(lambda_QF_est_all_runs,1,median,na.rm=T)
            best_lambda_index = which.max(lambda_QF_est[[i_alpha]])
            
            best_lambda[i_alpha] = lambda_values[[i_alpha]][best_lambda_index]
            model_QF_est[i_alpha] = lambda_QF_est[[i_alpha]][best_lambda_index]
            
            predicted_values[[i_alpha]] = matrix(rep(NA,n_instance*n_class),ncol=n_class)
            for (i_instance in 1:n_instance) {
                for (i_class in 1:n_class) {
                    predicted_values[[i_alpha]][i_instance,i_class] =  sum(predicted_values_all_lambda[seq(i_instance,n_instance*n_run,by=n_instance),
                    best_lambda_index]==class[i_class])/n_run
                }
            }
            
            for (i_class in 1:n_class) {
                weight_tot = rowSums(feature_freq_per_lambda[[best_lambda_index]][[i_class]])
                feature_coef_wmean[[i_class]][,i_alpha] = rowSums(feature_coef_per_lambda[[best_lambda_index]][[i_class]]*feature_freq_per_lambda[[best_lambda_index]][[i_class]],na.rm=T)/weight_tot
                for (i_feature in 1:n_feature) {
                    feature_coef_wsd[[i_class]][i_feature,i_alpha] = sqrt(sum(feature_freq_per_lambda[[best_lambda_index]][[i_class]][i_feature,]/weight_tot[i_feature] * (feature_coef_per_lambda[[best_lambda_index]][[i_class]][i_feature,] - feature_coef_wmean[[i_class]][i_feature,i_alpha])^2,na.rm=T))
                }
                feature_freq_mean[[i_class]][,i_alpha] = apply(feature_freq_per_lambda[[best_lambda_index]][[i_class]],1,mean)
                feature_freq_sd[[i_class]][,i_alpha] = apply(feature_freq_per_lambda[[best_lambda_index]][[i_class]],1,sd)
            }
            
            # permutation-based null
            null_QF_est_all_runs = matrix(rep(NA,n_run*n_perm_null),ncol=n_perm_null)
            null_feature_coef = vector("list",n_class)
            null_feature_freq = vector("list",n_class)
            for (i_class in 1:n_class) {
                null_feature_coef[[i_class]] = matrix(rep(NA,n_feature*n_run*n_perm_null),ncol=n_run*n_perm_null)
                null_feature_freq[[i_class]] = matrix(rep(NA,n_feature*n_run*n_perm_null),ncol=n_run*n_perm_null)
            }
            pb <- progress_bar$new(
            format = paste0("  running NULL for alpha = ",alpha[i_alpha]," [:bar] :percent in :elapsed"),
            total = n_run, clear = T, width= 60)
            for (i_run in 1:n_run) {
                for (i_perm_null in 1:n_perm_null) {   # permutation loop
                    fold_distrib_OK = F
                    fold_distrib_fail = 0
                    while (!fold_distrib_OK) { # for categorical models, we must check that each class is in more than 1 fold.
                        y_RDM = sample(y) # we randomly permute the response vector
                        if (sum(apply(table(foldid_per_run[[i_alpha]][,i_run],y_RDM)>0,2,sum)>1)==n_class) {
                            fold_distrib_OK = T
                        } else {
                            fold_distrib_fail = fold_distrib_fail + 1
                            if (fold_distrib_fail>fold_distrib_fail.max) {
                                stop("Failure in class distribution across cross-validation folds. Increase n_fold, remove very small classes, or re-run with larger fold_distrib_fail.max\n")
                            }
                        }
                    }
                    null_predicted_values = rep(NA,n_instance)
                    null_feature_coef_per_run = vector("list",n_class)
                    for (i_class in 1:n_class) {
                        null_feature_coef_per_run[[i_class]] = matrix(rep(NA,n_feature*n_fold),ncol=n_fold)
                    }
                    for (i_fold in 1:n_fold) {
                        instance_in_bag = foldid_per_run[[i_alpha]][,i_run]!=i_fold
                        fit = glmnet(x[instance_in_bag,],y_RDM[instance_in_bag],alpha=alpha[i_alpha],family=family,lambda=lambda_values[[i_alpha]][best_lambda_index])
                        null_predicted_values[which(!instance_in_bag)] = predict(fit, x[!instance_in_bag,], s=lambda_values[[i_alpha]][best_lambda_index], type=prediction_type)
                        for (i_class in 1:n_class) {
                            null_feature_coef_per_run[[i_class]][,i_fold] = coef(fit)[[i_class]][-1,] # we remove the intercept
                        }
                    }
                    null_QF_est_all_runs[i_run,i_perm_null] = QF(null_predicted_values,y_RDM)
                    for (i_class in 1:n_class) {
                        is.na(null_feature_coef_per_run[[i_class]]) <- null_feature_coef_per_run[[i_class]] == 0
                        null_feature_coef[[i_class]][,(i_run-1)*n_perm_null+i_perm_null] = rowMeans(null_feature_coef_per_run[[i_class]], na.rm=T) # we obtain the mean (nonzero) coefficients over folds.
                        null_feature_freq[[i_class]][,(i_run-1)*n_perm_null+i_perm_null] = rowSums(!is.na(null_feature_coef_per_run[[i_class]]))/n_fold
                    }
                }
                pb$tick()
            }
            
            for (i_class in 1:n_class) {
                weight_tot = rowSums(null_feature_freq[[i_class]])
                null_feature_coef_wmean[[i_class]][,i_alpha] = rowSums(null_feature_coef[[i_class]]*null_feature_freq[[i_class]],na.rm=T)/weight_tot
                for (i_feature in 1:n_feature) {
                    null_feature_coef_wsd[[i_class]][i_feature,i_alpha] = sqrt(sum(null_feature_freq[[i_class]][i_feature,]/weight_tot[i_feature] * (null_feature_coef[[i_class]][i_feature,] - null_feature_coef_wmean[[i_class]][i_feature,i_alpha])^2,na.rm=T))
                }
                null_feature_freq_mean[[i_class]][,i_alpha] = apply(null_feature_freq[[i_class]],1,mean)
                null_feature_freq_sd[[i_class]][,i_alpha] = apply(null_feature_freq[[i_class]],1,sd)
            }
            
            # Comparisons of model vs null
            n_tail = 0
            n_tot = 0
            for (i_run in 1:n_run) {
                null_above_model = null_QF_est_all_runs[i_run,]>lambda_QF_est_all_runs[best_lambda_index,i_run]
                n_tail = n_tail + sum(null_above_model,na.rm=T)
                n_tot = n_tot + sum(!is.na(null_above_model))
            }
            QF_model_vs_null_pval[i_alpha] = (n_tail+1)/(n_tot+1) # correction based on Phipson & Smyth (2010)
            
            for (i_class in 1:n_class) {
                for (i_feature in 1:n_feature) {
                    n_coef = 0
                    n_tail_coef = 0
                    n_tail_freq = 0
                    for (i_run in 1:n_run) {
                        coef_null_vs_model = abs(null_feature_coef[[i_class]][i_feature,(i_run-1)*n_perm_null+(1:n_perm_null)])>=abs(feature_coef_per_lambda[[best_lambda_index]][[i_class]][i_feature,i_run])
                        n_coef = n_coef + sum(!is.na(coef_null_vs_model))
                        n_tail_coef = n_tail_coef + sum(coef_null_vs_model,na.rm=T)
                        n_tail_freq = n_tail_freq + sum(null_feature_freq[[i_class]][i_feature,(i_run-1)*n_perm_null+(1:n_perm_null)]>=feature_freq_per_lambda[[best_lambda_index]][[i_class]][i_feature,i_run])
                    }
                    feature_coef_model_vs_null_pval[[i_class]][i_feature,i_alpha] = (n_tail_coef+1)/(n_coef+1)
                    feature_freq_model_vs_null_pval[[i_class]][i_feature,i_alpha] = (n_tail_freq+1)/(n_run*n_perm_null+1)
                }
            }
            n_alpha_eff = i_alpha # to keep track of fully completed cycles
            cat("alpha = ",alpha[i_alpha]," completed.\n")
        } # end of alpha loop
        return_obj(n_alpha_eff)
    }, error = function(e) {
        cat("Error during execution of alpha = ",alpha[i_alpha],"\n")
        if (n_alpha_eff>0) {
            return_obj(n_alpha_eff)
        }
    }) # end of tryCatch
}
