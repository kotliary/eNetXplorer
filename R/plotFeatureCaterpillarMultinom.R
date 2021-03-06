plotFeatureCaterpillarMultinom <- function (
x, alpha.index, stat, feature.all, feature.pval.thres, feature.set, feature.top.n,
signif.code, xlab, ylab, main, col.main, cex.main, line, subtitle, col.subtitle, line.subtitle,
cex.subtitle, cexRow, cex.lab, legend,
...) {
    for (i_alpha in alpha.index) {
        class = levels(x$response)
        n_class = length(class)
        for (i_class in 1:n_class) {
            if (stat=="freq") {
                feature_mean = x$feature_freq_mean[[i_class]][,i_alpha]
                feature_sd = x$feature_freq_sd[[i_class]][,i_alpha]
                null_feature_mean = x$null_feature_freq_mean[[i_class]][,i_alpha]
                null_feature_sd = x$null_feature_freq_sd[[i_class]][,i_alpha]
                pval = x$feature_freq_model_vs_null_pval[[i_class]][,i_alpha]
                main.def = "frequencies"
                if (is.null(xlab)) {
                    xlab.set = paste0("feature frequency for class ",class[i_class])
                } else {
                    xlab.set = xlab
                }
            } else if (stat=="coef") {
                feature_mean = x$feature_coef_wmean[[i_class]][,i_alpha]
                feature_sd = x$feature_coef_wsd[[i_class]][,i_alpha]
                null_feature_mean = x$null_feature_coef_wmean[[i_class]][,i_alpha]
                null_feature_sd = x$null_feature_coef_wsd[[i_class]][,i_alpha]
                pval = x$feature_coef_model_vs_null_pval[[i_class]][,i_alpha]
                main.def = "coefficients"
                if (is.null(xlab)) {
                    xlab.set = paste0("feature coefficient for class ",class[i_class])
                } else {
                    xlab.set = xlab
                }
            }
            n_feature = length(x$feature)
            o = order(pval)
            if (!feature.all) {
                if (!is.null(feature.pval.thres)) {
                    n_feature = sum(pval[o]<feature.pval.thres)
                } else if (!is.null(feature.set)) {
                    feature_select = which(x$feature%in%feature.set)
                    n_feature = length(feature_select)
                    o = feature_select[order(pval[feature_select])]
                } else {
                    n_feature = min(n_feature,feature.top.n)
                }
            }
            if (n_feature<length(x$feature)) {
                main.def = paste0("Selected feature ",main.def," ranked by p-value for alpha=",x$alpha[i_alpha])
            } else {
                main.def = paste0("Feature ",main.def," ranked by p-value for alpha=",x$alpha[i_alpha])
            }
            tryCatch({
                if (n_feature>1) {
                    o = rev(o[1:n_feature])
                    feature = x$feature[o]
                    feature_mean = feature_mean[o]
                    feature_sd = feature_sd[o]
                    null_feature_mean = null_feature_mean[o]
                    null_feature_sd = null_feature_sd[o]
                    pval = pval[o]
                    x_range = range(c(feature_mean-feature_sd,feature_mean+feature_sd,
                    null_feature_mean-null_feature_sd,null_feature_mean+null_feature_sd),na.rm=T)
                    y_range = c(1,n_feature)
                    if (stat=="freq") {
                        x_range[1] = max(x_range[1],0)
                        x_range[2] = min(x_range[2],1)
                        if (x_range[1]==x_range[2]) { # alpha=0
                            x_range = x_range[1] + c(-1,1)*0.1
                        }
                    }
                    if (is.null(ylab)) {
                        ylab = ""
                    }
                    if (is.null(main)) {
                        main.title = main.def
                    } else {
                        main.title = main
                    }
                    plot(x_range,y_range,type="n",xlab=xlab.set,ylab=ylab,yaxt="n",cex.lab=cex.lab, ...)
                    if (signif.code) {
                        signif_legend = "P-value significance codes:  <0.001 (***), <0.01 (**), <0.05 (*), <0.1 (.)"
                        signif_symbol = c("  .","  *"," **","***")
                        signif_pval_thres = c(0.10,0.05,0.01,0.001)
                        feature_signif = rep("   ",n_feature)
                        for (i_signif in 1:length(signif_symbol)) {
                            feature_signif[pval<signif_pval_thres[i_signif]] = signif_symbol[i_signif]
                        }
                        feature = paste(feature,feature_signif)
                    }
                    if (is.null(cexRow)) {
                        cexRow = min(1.6/log(n_feature),0.5)
                    }
                    axis(side=2,at=1:n_feature,labels=feature,las=2,cex.axis=cexRow,tck=-0.005)
                    abline(h=(1:n_feature),col="lightgray",lty="dotted")
                    if (signif.code) {
                        if (is.null(subtitle)) {
                            subtitle = signif_legend
                        }
                        title(subtitle,col.main=col.subtitle, line=line.subtitle, cex.main=cex.subtitle)
                    }
                    title(main.title, col.main=col.main, cex.main=cex.main)
                    points(null_feature_mean,1:n_feature,pch=16,cex=1,col="blue",lty=3,type="p")
                    suppressWarnings(
                    arrows(pmax(x_range[1],null_feature_mean-null_feature_sd),1:n_feature,
                    pmin(x_range[2],null_feature_mean+null_feature_sd),1:n_feature,col="blue",length=0.025,angle=90,code=3,lty=2)
                    )
                    points(feature_mean,1:n_feature,pch=16,cex=1,col="red",lty=3,type="p")
                    suppressWarnings(
                    arrows(pmax(x_range[1],feature_mean-feature_sd),1:n_feature,
                    pmin(x_range[2],feature_mean+feature_sd),1:n_feature,col="red",length=0.025,angle=90,code=3,lty=2)
                    )
                    if (legend) {
                        legend("topright",inset=c(0,-0.165),legend=c("model","null"),
                        pch=16,col=c("red","blue"),xpd=T,cex=0.75)
                    }
                }
            }, error = function(e) {
                cat("Error in plotFeatureCaterpillar for alpha = ",x$alpha[i_alpha],"\n")
            }) # end of tryCatch
        }
    }
}
