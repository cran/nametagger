
#' @title Load a Named Entity Recognition
#' @description Load a Named Entity Recognition from your hard disk
#' @param file character string with the path to the file on disk
#' @export
#' @return an object of class nametagger 
#' @examples 
#' path  <- system.file(package = "nametagger", "models", "exampletagger.ner")
#' model <- nametagger_load_model(path)
#' model
nametagger_load_model <- function(file){
  model <- nametag_load_model(file)
  info <- nametag_info(model)
  model <- list(file_model = file, model = model, labels = info$entities, gazetteers = info$gazetteers)
  class(model) <- "nametagger"
  model
}


#' @export
print.nametagger <- function(x, ...){
  fsize <- file.info(x$file_model)$size
  cat(sprintf("Nametag model saved at %s", x$file_model), sep = "\n")
  cat(sprintf("  size of the model in Mb: %s", round(fsize/(2^20), 2)), sep = "\n")
  cat(sprintf("  number of categories: %s", length(x$labels)), sep = "\n")
  cat(sprintf("  category labels: %s", paste(x$labels, collapse = ", ")), sep = "\n")
}


#' @title Perform Named Entity Recognition on tokenised text
#' @description Perform Named Entity Recognition on tokenised text using a nametagger model
#' @param object an object of class \code{nametagger} as returned by \code{\link{nametagger_load_model}}
#' @param newdata a data.frame with tokenised sentences. This data.frame should contain the columns doc_id, sentence_id and text where
#' \code{text} contains tokens in vertical format, meaning each token is put on a new line. Column doc_id should be of type character, column sentence_id of type integer.
#' @param split a regular expression used to split \code{newdata}. Only used if \code{newdata} is a character vector containing text which is not tokenised
#' @param ... not used 
#' @export
#' @return a data.frame with columns doc_id, sentence_id, token and entity
#' @examples 
#' path  <- system.file(package = "nametagger", "models", "exampletagger.ner")
#' model <- nametagger_load_model(path)
#' model
#' 
#' x <- c("I ga naar Brussel op reis.", "Goed zo dat zal je deugd doen Karel")
#' entities <- predict(model, x, split = "[[:space:][:punct:]]+")                          
#' entities
#' 
#' \donttest{
#' model <- nametagger_download_model("english-conll-140408", model_dir = tempdir())
#' 
#' x <- data.frame(doc_id = c(1, 1, 2),
#'                 sentence_id = c(1, 2, 1),
#'                 text = c("I\nlive\nin\nNew\nYork\nand\nI\nwork\nfor\nApple\nInc.", 
#'                          "Why\ndon't\nyou\ncome\nvisit\nme", 
#'                          "Good\nnews\nfrom\nAmazon\nas\nJohn\nworks\nthere\n."))
#' entities <- predict(model, x)                          
#' entities
#' }
predict.nametagger <- function(object, newdata, split = "[[:space:]]+", ...){
  if(is.character(newdata)){
    # newdata <- data.frame(doc_id = seq_along(newdata), 
    #                       sentence_id = seq_along(newdata), 
    #                       text = newdata, 
    #                       stringsAsFactors = FALSE)
    # newdata <- udpipe::strsplit.data.frame(newdata, term = c("text"), group = c("doc_id", "sentence_id"), split = split)
    newdata <- splitter(newdata, split = split)
  }
  stopifnot(is.data.frame(newdata))
  stopifnot(all(c("doc_id", "sentence_id", "text") %in% colnames(newdata)))
  nametag_annotate(object$model, newdata$text, newdata$doc_id, newdata$sentence_id)
}

splitter <- function(x, split){
  unlist_tokens <- function(x){
    stopifnot(is.list(x))
    if(is.null(names(x))){
      doc_id <- rep(x = as.character(seq_along(x)), times = sapply(x, length))
    }else{
      doc_id <- rep(x = names(x), times = sapply(x, length)) 
    }
    sentence_id <- rep(x = seq_along(x), times = sapply(x, length))
    token  <- unlist(x, use.names = FALSE, recursive = FALSE)
    if(length(token) == 0){
      x <- data.frame(doc_id = character(), 
                      sentence_id = integer(),
                      text = character(), 
                      stringsAsFactors = FALSE)
    }else{
      x <- data.frame(doc_id = doc_id, 
                      sentence_id = sentence_id,
                      text = token, 
                      stringsAsFactors = FALSE)  
    }
    x
  }
  tokens <- strsplit(x, split = split)
  tokens <- unlist_tokens(tokens)
  tokens <- tokens[!is.na(tokens$text), ]
  tokens <- tokens[nchar(tokens$text) > 0, ]
  rownames(tokens) <- NULL
  tokens
}


#' @title Save a tokenised dataset as nametagger train data
#' @description Save a tokenised dataset as nametagger train data
#' @param x a tokenised data.frame with columns doc_id, sentence_id, token containing 1 row per token. \cr
#' In addition it can have columns lemma and pos representing the lemma and the parts-of-speech tag of the token
#' @param file the path to the file where the training data will be saved
#' @export
#' @return invisibly an object of class nametagger_traindata which is a list with elements
#' \itemize{
#' \item{data: a character vector of text in the nametagger format}
#' \item{file: the path to the file where \code{data} is saved to}
#' }
#' @examples 
#' data(europeananews)
#' x <- subset(europeananews, doc_id %in% "enp_NL.kb.bio")
#' x <- head(x, n = 250)
#'
#' path <- "traindata.txt" 
#' \dontshow{
#' path <- tempfile("traindata_", fileext = ".txt")
#' }
#' bio  <- write_nametagger(x, file = path)
#' str(bio)
#' 
#' \dontshow{
#' # clean up for CRAN
#' file.remove(path)
#' }
write_nametagger <- function(x, file = tempfile(fileext = ".txt", pattern = "nametagger_")){
  if("lemma" %in% colnames(x)){
    x$form <- paste(x$token, x$lemma, sep = " ")
    if("pos" %in% colnames(x)){
      x$form <- paste(x$form, x$pos, sep = " ")
    }
  }else{
    x$form <- x$token
  }
  x$content <- paste(x$form, x$entity, sep = "\t")
  x <- split(x, list(x$doc_id, x$sentence_id))
  x <- sapply(x, FUN=function(x){
    paste(x$content, collapse = "\n")
  }, USE.NAMES = FALSE)
  con <- base::file(file, "w")
  writeLines(x, con = con, sep = "\n\n")
  close(con)
  x <- list(data = x, file = file)
  class(x) <- c("nametagger_traindata")
  invisible(x)
}




#' @title Train a Named Entity Recognition Model using NameTag
#' @description Train a Named Entity Recognition Model using NameTag. Details at \url{https://ufal.mff.cuni.cz/nametag/1}.
#' @param x.train a file with training data or a data.frame which can be passed on to \code{\link{write_nametagger}}
#' @param x.test optionally, a file with test data or a data.frame which can be passed on to \code{\link{write_nametagger}}
#' @param type either one of 'generic', 'english' or 'czech'
#' @param tagger either one of 'trivial' (no lemma used in the training data), 'external' (you provided your own lemma in the training data)
#' @param iter the number of iterations performed when training each stage of the recognizer. With more iterations, training take longer (the recognition time is unaffected), but the model gets over-trained when too many iterations are used. Values from 10 to 30 or 50 are commonly used.
#' @param lr learning rates used. Should be a vector of length 2 where 
#' \itemize{
#' \item{element 1: learning rate used in the first iteration of SGD training method of the log-linear model. Common value is 0.1.}
#' \item{element 2: learning rate used in the last iteration of SGD training method of the log-linear model. Common values are in range from 0.1 to 0.001, with 0.01 working reasonably well.}
#' }
#' @param lambda the value of Gaussian prior imposed on the weights. In other words, value of L2-norm regularizer. Common value is either 0 for no regularization, or small real number like 0.5.
#' @param stages the number of stages performed during recognition. Common values are either 1 or 2. With more stages, the model is larger and recognition is slower, but more accurate.
#' @param weight_missing default value of missing weights in the log-linear model. Common values are small negative real numbers like -0.2.
#' @param control the result of a call to \code{\link{nametagger_options}} a file with predictive feature transformations serving as predictive elements in the model
#' @param file path to the filename where the model will be saved
#' @export
#' @return an object of class \code{nametagger} containing an extra list element called stats containing information on the evolution of the log probability and the accuracy on the training and optionally the test set
#' @examples 
#' data(europeananews)
#' x <- subset(europeananews, doc_id %in% "enp_NL.kb.bio")
#' traindata <- subset(x, sentence_id >  100)
#' testdata  <- subset(x, sentence_id <= 100)
#' path <- "nametagger-nl.ner" 
#' \dontshow{
#' path <- tempfile("nametagger-nl_", fileext = ".ner")
#' traindata <- subset(x, sentence_id >  100 & sentence_id < 300)
#' testdata  <- subset(x, sentence_id <= 100)
#' } 
#' opts <- nametagger_options(file = path,
#'                            token = list(window = 2),
#'                            token_normalisedsuffix = list(window = 0, from = 1, to = 4),
#'                            ner_previous = list(window = 2),
#'                            time = list(use = TRUE),
#'                            url_email = list(url = "URL", email = "EMAIL"))
#' \dontshow{
#' model <- nametagger(x.train = traindata, x.test = testdata,
#'                     iter = 1, lambda = 0.5, control = opts)
#' }
#' \donttest{
#' model <- nametagger(x.train = traindata, 
#'                     x.test = testdata,
#'                     iter = 30, lambda = 0.5,
#'                     control = opts)
#' }
#' model
#' model$stats
#' plot(model$stats$iteration, model$stats$logprob, type = "b")
#' plot(model$stats$iteration, model$stats$accuracy_train, type = "b", ylim = c(95, 100))
#' lines(model$stats$iteration, model$stats$accuracy_test, type = "b", lty = 2, col = "red")
#' \dontshow{if(require(udpipe))\{}
#' predict(model, 
#'         "Ik heet Karel je kan me bereiken op paul@duchanel.be of www.duchanel.be", 
#'         split = "[[:space:]]+")
#' \dontshow{\} # End of main if statement running only if the required packages are installed}
#' 
#' features <- system.file(package = "nametagger", 
#'                         "models", "features_default.txt")
#' cat(readLines(features), sep = "\n")
#' path_traindata <- "traindata.txt" 
#' \dontshow{
#' path_traindata <- tempfile("traindata_", fileext = ".txt")
#' }
#' write_nametagger(x, file = path_traindata)
#' \dontshow{
#' model <- nametagger(path_traindata, iter = 1, control = features, file = path)
#' }
#' \donttest{
#' model <- nametagger(path_traindata, iter = 30, control = features, file = path)
#' model
#' }
#' 
#' \dontshow{
#' # clean up for CRAN
#' file.remove(path)
#' file.remove(path_traindata)
#' }
nametagger <- function(x.train, 
                       x.test = NULL,
                       iter = 30L,
                       lr = c(0.1, 0.01),
                       lambda = 0.5,
                       stages = 1L,
                       weight_missing = -0.2,
                       control = nametagger_options(token = list(window = 2)), 
                       type    = if(inherits(control, "nametagger_options")) control$type else "generic",
                       tagger  = if(inherits(control, "nametagger_options")) control$tagger else "trivial", 
                       file    = if(inherits(control, "nametagger_options")) control$file else "nametagger.ner"){
  #heldout_data – optional parameter with heldout data in the described format. If the heldout data is present, the accuracy of the heldout data classification is printed during training. The heldout data is not used in any other way. 
  opts <- control
  if(inherits(opts, "nametagger_options")){
    features_file <- tempfile(pattern = "nametagger_features_", fileext = ".txt")
    opts <- opts[setdiff(names(opts), c("file", "type", "tagger"))]
    opts <- unlist(opts)
    writeLines(text = opts, con = features_file)
  }else{
    stopifnot(file.exists(control))
    features_file <- control  
  }
  
  if(inherits(x.train, "data.frame")){
    file_traindata <- write_nametagger(x.train, file = tempfile(fileext = ".txt", pattern = sprintf("nametagger_train_%s", gsub("\\.", "", format(Sys.time(), "%Y%m%d%H%M%OS6")))))
    file_traindata <- file_traindata$file
    on.exit(file.remove(file_traindata))
  }else if(file.exists(x.train)){
    file_traindata <- x.train
  }else{
    stopifnot(sprintf("%s not found", x.train))
  }
  if(!is.null(x.test) && inherits(x.test, "data.frame")){
    file_holdout <- write_nametagger(x.test, file = tempfile(fileext = ".txt", pattern = sprintf("nametagger_test_%s", gsub("\\.", "", format(Sys.time(), "%Y%m%d%H%M%OS6")))))
    file_holdout <- file_holdout$file
    if(inherits(x.train, "data.frame")){
      on.exit({
        file.remove(file_traindata)
        file.remove(file_holdout)
      })  
    }else{
      on.exit({
        file.remove(file_holdout)
      }) 
    }
  }else if(is.null(x.test)){
    file_holdout <- "" 
  }else{
    file_holdout <- x.test
  }
  stopifnot(type %in% c("generic", "english", "czech"))
  stopifnot(tagger %in% c("trivial", "external") | grepl(pattern = "morphodita", tagger))
  iterations <- as.integer(iter)
  missing_weight <- as.numeric(weight_missing)
  initial_learning_rate <- as.numeric(lr[1])
  final_learning_rate <- as.numeric(lr[2])
  gaussian <- as.numeric(lambda)
  #hidden_layer – experimental support for hidden layer in the artificial neural network classifier. To not use the hidden layer (recommended), use 0. Otherwise, specify the number of neurons in the hidden layer. Please note that non-zero values will create enormous models, slower recognition and are not guaranteed to create models with better accuracy.
  hidden_layer <- 0L
  out <- utils::capture.output(
    nametag_train(modelname = file, file = file_traindata, 
                  type = type, 
                  features_file = features_file, input_type = tagger, 
                  stages = stages, 
                  iterations = iterations,
                  missing_weight = missing_weight, 
                  initial_learning_rate = initial_learning_rate, final_learning_rate = final_learning_rate,
                  gaussian = gaussian, hidden_layer = hidden_layer, 
                  has_holdout = nchar(file_holdout) > 0, heldout_file = file_holdout)
    )
  model <- nametagger_load_model(file)
  model$log <- out
  model$stats <- try(parse_training_log(out))
  model
}


parse_training_log <- function(x){
  # x <- c("Iteration 1: a 0.100, logprob -2.7850e+004, training acc 95.72%, heldout acc 97.62, done.", 
  #        "Iteration 2: a 0.010, logprob -1.9276e+004, training acc 96.68%, heldout acc 97.88, done."
  # )
  x <- grep(x = x, pattern = "Iteration", value = TRUE)
  x <- strsplit(x, ",")
  lr <- sapply(x, FUN=function(x) grep(x, pattern = "Iteration", value = TRUE), USE.NAMES = FALSE)
  if(length(lr) == 0){
    return(NULL)
  }
  lr <- strsplit(lr, ":")
  out <- list()
  out$iteration <- as.integer(sapply(lr, FUN=function(x) gsub(x = grep(x, pattern = "Iteration", value = TRUE), pattern = "Iteration", replacement = ""), USE.NAMES = FALSE))
  out$lr <- as.numeric(sapply(lr, FUN=function(x) gsub(x = grep(x, pattern = "a ", value = TRUE), pattern = "a", replacement = ""), USE.NAMES = FALSE))
  out$logprob <- as.numeric(sapply(x, FUN=function(x) gsub(pattern = " ", replacement = "", gsub(x = grep(x, pattern = "logprob", value = TRUE), pattern = "logprob", replacement = "")), USE.NAMES = FALSE))
  out$accuracy_train <- as.numeric(sapply(x, FUN=function(x) gsub(pattern = "%", replacement = "", gsub(x = grep(x, pattern = "training acc", value = TRUE), pattern = "training acc", replacement = "")), USE.NAMES = FALSE))
  out$accuracy_test <- as.numeric(sapply(x, FUN=function(x) gsub(pattern = "%", replacement = "", gsub(x = grep(x, pattern = "heldout acc", value = TRUE), pattern = "heldout acc", replacement = "")), USE.NAMES = FALSE))
  out
}

#' @title Define text transformations serving as predictive elements in the nametagger model
#' @description Define text transformations which are relevant in predicting your entity. 
#' Typical text transformations are the token itself, the lemma, the parts of speech tag of the token
#' or the token/lemma's and parts of speech tags in the neighbourhood of the word. \cr
#' 
#' Each argument should be a list with elements \code{use} and \code{window}. \cr
#' \itemize{
#' \item{\code{use} is a logical indicating if the transformation should be used in the model. }
#' \item{\code{window} specifies how many adjacent words can observe the feature template value of a given word. The default value of 0 denotes only the word in question, no surrounding words.}
#' }
#' If you specifiy the argument without specifying \code{use}, it will by default use it.
#' For arguments brown, gazetteers and gazetteers_enhanced, see the examples and 
#' the documentation at \url{https://ufal.mff.cuni.cz/nametag/1}.
#' @param file path to the filename where the model will be saved
#' @param type either one of 'generic', 'english' or 'czech'. See the documentation at the documentation at \url{https://ufal.mff.cuni.cz/nametag/1}.
#' @param tagger either one of 'trivial' (no lemma used in the training data), 'external' (you provided your own lemma in the training data)
#' @param token use forms as features
#' @param token_capitalised use capitalization of form as features
#' @param token_normalised use case normalized (first character as-is, others lowercased) forms as features
#' @param token_normalisedsuffix shortest longest – use suffixes of case normalized (first character as-is, others lowercased) forms of lengths between shortest and longest
#' @param lemma use raw lemmas as features
#' @param lemma_capitalised use capitalization of raw lemma as features
#' @param lemma_normalised use case normalized (first character as-is, others lowercased) raw lemmas as features
#' @param lemma_normalisedsuffix shortest longest – use suffixes of case normalized (first character as-is, others lowercased) raw lemmas of lengths between shortest and longest
#' @param pos use parts-of-speech tags as features
#' @param time recognize numbers which could represent hours, minutes, hour:minute time, days, months or years
#' @param url_email If an URL or an email is detected, it is immediately marked with specified named entity type and not used in further processing. The specified entity label to use can be specified with url and email (in that sequence)
#' @param ner_previous use named entities predicted by previous stage as features
#' @param brown file [prefix_lengths] – use Brown clusters found in the specified file. An optional list of lengths of cluster prefixes to be used in addition to the full Brown cluster can be specified. 
#                                       Each line of the Brown clusters file must contain two tab-separated columns, the first of which is the Brown cluster label and the second is a raw lemma.
#' @param gazetteers [files] – use given files as gazetteers. Each file is one gazetteers list independent of the others and must contain a set of lemma sequences, each on a line, represented as raw lemmas separated by spaces.
#' @param gazetteers_enhanced (form|rawlemma|rawlemmas) (embed_in_model|out_of_model) file_base entity [file_base entity ...] – use gazetteers from given files. Each gazetteer contains (possibly multiword) named entities per line. Matching of the named entities can be performed either using form, disambiguated rawlemma of any of rawlemmas proposed by the morphological analyzer. The gazetteers might be embedded in the model file or not; in either case, additional gazetteers are loaded during each startup. For each file_base specified in GazetteersEnhanced templates, three files are tried:
#' \itemize{
#' \item{file_base.txt: gazetteers used as features, representing each file_base with a unique feature}
#' \item{file_base.hard_pre.txt: matched named entities (finding non-overlapping entities, preferring the ones starting earlier and longer ones in case of ties) are forced to the specified entity type even before the NER model is executed}
#' \item{file_base.hard_post.txt: after running the NER model, tokens not recognized as entities are matched against the gazetteers (again finding non-overlapping entities, preferring the ones starting earlier and longer ones in case of ties) and marked as entity type if found}
#' }
#' @export
#' @return an object of class \code{nametagger_options} with transformation information to be used by \code{\link{nametagger}}
#' @examples 
#' opts <- nametagger_options(token = list(window = 2))
#' opts
#' opts <- nametagger_options(time = list(use = TRUE, window = 3),
#'                            token_capitalised = list(use = TRUE, window = 1),
#'                            ner_previous = list(use = TRUE, window = 5))
#' opts                            
#' opts <- nametagger_options(
#'   lemma_capitalised = list(window = 3),
#'   brown = list(window = 1, file = "path/to/brown/clusters/file.txt"),
#'   gazetteers = list(window = 1, 
#'                     file_loc = "path/to/txt/file1.txt", 
#'                     file_time = "path/to/txt/file2.txt"))
#' opts
#' opts <- nametagger_options(
#'   lemma_capitalised = list(window = 3),
#'   brown = list(window = 2, 
#'                file = "path/to/brown/clusters/file.txt"),
#'   gazetteers_enhanced = list(
#'     loc  = "LOC",  type_loc  = "form", save_loc  = "embed_in_model", file_loc  = "pathto/loc.txt",  
#'     time = "TIME", type_time = "form", save_time = "embed_in_model", file_time = "pathto/time.txt")
#'     )
#' opts
nametagger_options <- function(file = "nametagger.ner", 
                               type = c("generic", "english", "czech"),
                               tagger = c("trivial", "external"),
                               token = list(use = FALSE, window = 1),
                               token_capitalised = list(use = FALSE, window = 0),
                               token_normalised = list(use = FALSE, window = 0),
                               token_normalisedsuffix = list(use = FALSE, window = 0, from = 1, to = 4),
                               lemma = list(use = FALSE, window = 0),
                               lemma_capitalised = list(use = FALSE, window = 0),
                               lemma_normalised = list(use = FALSE, window = 0),
                               lemma_normalisedsuffix = list(use = FALSE, window = 0, from = 1, to = 4),
                               pos = list(use = tagger == "external", window = 0),
                               time = list(use = FALSE, window = 0),
                               url_email = list(use = FALSE, url = "URL", email = "EMAIL"),
                               ner_previous = list(use = FALSE, window = 0),
                               brown = list(use = FALSE, window = 0),
                               gazetteers = list(use = FALSE, window = 0),
                               gazetteers_enhanced = list(use = FALSE)){
  type <- match.arg(type)
  tagger <- match.arg(tagger)
  combine <- function(x, label){
    ldots <- x[setdiff(names(x), c("window", "use"))]
    ldots <- unlist(ldots)
    ldots <- paste(ldots, collapse = " ")
    if(!"use" %in% names(x) || x$use){
      if("window" %in% names(x)){
        return(sprintf("%s/%s %s", label, x$window, ldots))  
      }else{
        return(sprintf("%s %s", label, ldots))
      }
      
    }else{
      return(NULL)
    }
  }
  
  out <- list()
  out$file <- file
  out$type <- type
  out$tagger <- tagger
  out$header <- sprintf("## file: %s\n## type: %s\n## tagger: %s", file, type, tagger)
  out$token <- combine(token, "Form")
  out$token_capitalised <- combine(token_capitalised, "FormCapitalization")
  out$token_normalised <- combine(token_normalised, "FormCaseNormalized")
  out$token_normalisedsuffix <- combine(token_normalisedsuffix, "FormCaseNormalizedSuffix")
  out$lemma <- combine(lemma, "RawLemma")
  out$lemma_capitalised <- combine(lemma_capitalised, "RawLemmaCapitalization")
  out$lemma_normalised <- combine(lemma_normalised, "RawLemmaCaseNormalized")
  out$lemma_normalisedsuffix <- combine(lemma_normalisedsuffix, "RawLemmaCaseNormalizedSuffix")
  out$pos <- combine(pos, "Tag")
  out$time <- combine(time, "NumericTimeValue")
  out$url_email <- combine(url_email, "URLEmailDetector")
  out$ner_previous <- combine(ner_previous, "PreviousStage")
  out$brown <- combine(brown, "BrownClusters")
  out$gazetteers <- combine(gazetteers, "Gazetteers")
  out$gazetteers_enhanced <- combine(gazetteers_enhanced, "GazetteersEnhanced")
  if(length(out[setdiff(names(out), c("file", "type", "tagger", "header"))]) == 0){
    stop("Please provide at least one text feature to use in the model")
  }
  class(out) <- "nametagger_options"
  
  # Sentence processors
  #Form/2
  #Lemma/2
  #RawLemma/2
  #RawLemmaCapitalization/2
  #Tag/2
  #NumericTimeValue/1
  
  # Form – use forms as features
  # FormCapitalization – use capitalization of form as features
  # FormCaseNormalized – use case normalized (first character as-is, others lowercased) forms as features
  # FormCaseNormalizedSuffix shortest longest – use suffixes of case normalized (first character as-is, others lowercased) forms of lengths between shortest and longest
  # Lemma – use lemma ids as a feature
  # RawLemma – use raw lemmas as features
  # RawLemmaCapitalization – use capitalization of raw lemma as features
  # RawLemmaCaseNormalized – use case normalized (first character as-is, others lowercased) raw lemmas as features
  # RawLemmaCaseNormalizedSuffix shortest longest – use suffixes of case normalized (first character as-is, others lowercased) raw lemmas of lengths between shortest and longest
  # Tag – use tags as features
  # URLEmailDetector url_type email_type – detect URLs and emails. If an URL or an email is detected, it is immediately marked with specified named entity type and not used in further processing.
  # NumericTimeValue – recognize numbers which could represent hours, minutes, hour:minute time, days, months or years
  # PreviousStage – use named entities predicted by previous stage as features

  # BrownClusters file [prefix_lengths] – use Brown clusters found in the specified file. An optional list of lengths of cluster prefixes to be used in addition to the full Brown cluster can be specified. 
  #                                       Each line of the Brown clusters file must contain two tab-separated columns, the first of which is the Brown cluster label and the second is a raw lemma.
  # CzechAddContainers – add CNEC containers (currently only P and T)
  # CzechLemmaTerm – feature template specific for Czech morphological system by Jan Hajič (Hajič 2004). The term information (personal name, geographic name, ...) specified in lemma comment are used as features.
  
  # Gazetteers [files] – use given files as gazetteers. Each file is one gazetteers list independent of the others and must contain a set of lemma sequences, each on a line, represented as raw lemmas separated by spaces.
  # GazetteersEnhanced (form|rawlemma|rawlemmas) (embed_in_model|out_of_model) file_base entity [file_base entity ...] – use gazetteers from given files. Each gazetteer contains (possibly multiword) named entities per line. Matching of the named entities can be performed either using form, disambiguated rawlemma of any of rawlemmas proposed by the morphological analyzer. The gazetteers might be embedded in the model file or not; in either case, additional gazetteers are loaded during each startup. For each file_base specified in GazetteersEnhanced templates, three files are tried:
  #   file_base.txt: gazetteers used as features, representing each file_base with a unique feature
  # file_base.hard_pre.txt: matched named entities (finding non-overlapping entities, preferring the ones starting earlier and longer ones in case of ties) are forced to the specified entity type even before the NER model is executed
  # file_base.hard_post.txt: after running the NER model, tokens not recognized as entities are matched against the gazetteers (again finding non-overlapping entities, preferring the ones starting earlier and longer ones in case of ties) and marked as entity type if found
  out
  
}

#' @export
print.nametagger_options <- function(x, ...){
  x <- x[setdiff(names(x), c("file", "type", "tagger"))]
  x <- unlist(x)
  cat(x, sep = "\n")
}



#' @title Download a Nametag model
#' @description Download a Nametag model. Note that models have licence CC-BY-SA-NC. 
#' More details at \url{https://ufal.mff.cuni.cz/nametag/1}.
#' @param language 'english-conll-140408'
#' @param model_dir a path where the model will be downloaded to.
#' @return an object of class nametagger 
#' @references \url{https://lindat.mff.cuni.cz/repository/xmlui/handle/11234/1-3118}
#' @export
#' @examples 
#' \donttest{
#' model <- nametagger_download_model("english-conll-140408", model_dir = tempdir())
#' }
nametagger_download_model <- function(language = c("english-conll-140408"), model_dir = tempdir()){
  language <- match.arg(language)
  f <- file.path(tempdir(), "english-conll-140408.zip")
  download.file(url = "https://lindat.mff.cuni.cz/repository/xmlui/bitstream/handle/11234/1-3118/english-conll-140408.zip?sequence=1&isAllowed=y",
                destfile = f, mode = "wb")
  f <- utils::unzip(f, exdir = tempdir(), files = "english-conll-140408/english-conll-140408.ner")
  from <- file.path(tempdir(), "english-conll-140408/english-conll-140408.ner")
  to <- file.path(model_dir, "english-conll-140408.ner")
  file.copy(from, to = to, overwrite = TRUE)
  nametagger_load_model(to)
}