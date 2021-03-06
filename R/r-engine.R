
estimate_r <- function(training, validation, trt, cens, deterministic, shift,
                       tau, node_list, learners = NULL, pb, sl_weights) {

  # global setup
  nt <- nrow(training)
  nv <- nrow(validation)
  rt <- list(natural = matrix(nrow = nt, ncol = tau),
             shifted = matrix(nrow = nt, ncol = tau))
  rv <- list(natural = matrix(nrow = nv, ncol = tau),
             shifted = matrix(nrow = nv, ncol = tau))

  for (t in 1:tau) {

    # setup
    i     <- rep(create_censoring_indicators(training, cens, t)$j, 2) # using j because we want everyone observed at current time despite censoring at t + 1
    d     <- rep(create_determ_indicators(training, deterministic, t), 2)
    stcks <- create_r_stacks(training, validation, trt, cens, shift, t, nt, nv)

    # create sl3 tasks for training and validation sets
    fit_task   <- initiate_sl3_task(subset(stcks$train, i & !d), "si", c(node_list[[t]], cens[[t]]), "binomial", "id")
    tpred_task <- sw(initiate_sl3_task(stcks$train, "si", c(node_list[[t]], cens[[t]]), "binomial", "id")) # sl3 will impute missing here, this is okay because all censored are multiplied by 0 below
    vpred_task <- sw(initiate_sl3_task(stcks$valid, "si", c(node_list[[t]], cens[[t]]), "binomial", "id")) # same here
    ensemble   <- initiate_ensemble("binomial", learners)

    # run SL
    fit             <- run_ensemble(ensemble, fit_task)
    sl_weights[[t]] <- extract_sl_weights(fit)

    # ratios training
    pred            <- bound(predict_sl3(fit, tpred_task), .Machine$double.eps)
    rat             <- pred * rep(create_censoring_indicators(training, cens, t)$i, 2) / (1 - bound(pred)) # rep() serves as indicator of missing at next time
    rt$natural[, t] <- rat[stcks$train$si == 0]
    rt$shifted[, t] <- rat[stcks$train$si == 1]
    rt$natural[create_determ_indicators(training, deterministic, t), t] <- 1
    rt$shifted[create_determ_indicators(training, deterministic, t), t] <- 1

    # ratios validation
    pred            <- bound(predict_sl3(fit, vpred_task), .Machine$double.eps)
    rat             <- pred * rep(create_censoring_indicators(validation, cens, t)$i, 2) / (1 - bound(pred)) # rep() serves as indicator of missing at next time
    rv$natural[, t] <- rat[stcks$valid$si == 0]
    rv$shifted[, t] <- rat[stcks$valid$si == 1]
    rv$natural[create_determ_indicators(validation, deterministic, t), t] <- 1
    rv$shifted[create_determ_indicators(validation, deterministic, t), t] <- 1

    # update progress bar
    pb()

  }

  out <- list(train = rt,
              valid = rv,
              sl_weights = sl_weights)

  # returns
  return(out)
}

ratio_dr <- function(ratios, V) {
  out <- list()
  for (i in 1:V) {
      out[[i]] <- list()
      out[[i]]$train <- check_extreme_ratio(
        matrix(t(apply(ratios[[i]]$train$natural, 1, cumprod)),
               nrow = nrow(ratios[[i]]$train$natural),
               ncol = ncol(ratios[[i]]$train$natural))
      )
      out[[i]]$valid <- check_extreme_ratio(
        matrix(t(apply(ratios[[i]]$valid$natural, 1, cumprod)),
               nrow = nrow(ratios[[i]]$valid$natural),
               ncol = ncol(ratios[[i]]$valid$natural))
      )
      out[[i]]$sl_weights <- ratios[[i]]$sl_weights
  }
  return(out)
}

ratio_ipw <- function(ratio) {
  out <-
    list(r = check_extreme_ratio(matrix(
      t(apply(ratio$r, 1, cumprod)),
      nrow = nrow(ratio$r),
      ncol = ncol(ratio$r)
    )),
    sl_weights = ratio$sl_weights)
  return(out)
}

ratio_sdr <- function(ratio, tau, max_tau) {
  out <- t(apply(ratio$natural[, (tau + 1):max_tau, drop = FALSE], 1, cumprod))
  if (tau == max_tau - 1) out <- t(out)
  return(check_extreme_ratio(out))
}
