generateFoldID <- function(n_instance, n_fold) {
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
  return(foldid)
}
