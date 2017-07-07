
stopOnLine <- function(lineNum, line, msg){
  stop("Error on line #", lineNum, ": '", line, "' - ", msg)
}

#' @param lineNum The line number just above the function we're documenting
#' @param file A character vector representing all the lines in the file
#' @noRd
parseBlock <- function(lineNum, file){
  path <- NULL
  verbs <- NULL
  preempt <- NULL
  filter <- NULL
  image <- NULL
  serializer <- NULL
  assets <- NULL
  params <- NULL
  comments <- ""
  responses <- NULL
  while (lineNum > 0 && (stri_detect_regex(file[lineNum], pattern="^#['\\*]") || stri_trim_both(file[lineNum]) == "")){

    line <- file[lineNum]

    epMat <- stringi::stri_match(line, regex="^#['\\*]\\s*@(get|put|post|use|delete|head)(\\s+(.*)$)?")
    if (!is.na(epMat[1,2])){
      p <- stri_trim_both(epMat[1,4])

      if (is.na(p) || p == ""){
        stopOnLine(lineNum, line, "No path specified.")
      }

      verbs <- c(verbs, enumerateVerbs(epMat[1,2]))
      path <- p
    }

    filterMat <- stringi::stri_match(line, regex="^#['\\*]\\s*@filter(\\s+(.*)$)?")
    if (!is.na(filterMat[1,1])){
      f <- stri_trim_both(filterMat[1,3])

      if (is.na(f) || f == ""){
        stopOnLine(lineNum, line, "No @filter name specified.")
      }

      if (!is.null(filter)){
        # Must have already assigned.
        stopOnLine(lineNum, line, "Multiple @filters specified for one function.")
      }

      filter <- f
    }

    preemptMat <- stringi::stri_match(line, regex="^#['\\*]\\s*@preempt(\\s+(.*)\\s*$)?")
    if (!is.na(preemptMat[1,1])){
      p <- stri_trim_both(preemptMat[1,3])
      if (is.na(p) || p == ""){
        stopOnLine(lineNum, line, "No @preempt specified")
      }
      if (!is.null(preempt)){
        # Must have already assigned.
        stopOnLine(lineNum, line, "Multiple @preempts specified for one function.")
      }
      preempt <- p
    }

    assetsMat <- stringi::stri_match(line, regex="^#['\\*]\\s*@assets(\\s+(\\S*)(\\s+(\\S+))?\\s*)?$")
    if (!is.na(assetsMat[1,1])){
      dir <- stri_trim_both(assetsMat[1,3])
      if (is.na(dir) || dir == ""){
        stopOnLine(lineNum, line, "No directory specified for @assets")
      }
      prefixPath <- stri_trim_both(assetsMat[1,5])
      if (is.na(prefixPath) || prefixPath == ""){
        prefixPath <- "/public"
      }
      if (!is.null(assets)){
        # Must have already assigned.
        stopOnLine(lineNum, line, "Multiple @assets specified for one entity.")
      }
      assets <- list(dir=dir, path=prefixPath)
    }

    serMat <- stringi::stri_match(line, regex="^#['\\*]\\s*@serializer(\\s+([^\\s]+)\\s*(.*)\\s*$)?")
    if (!is.na(serMat[1,1])){
      s <- stri_trim_both(serMat[1,3])
      if (is.na(s) || s == ""){
        stopOnLine(lineNum, line, "No @serializer specified")
      }
      if (!is.null(serializer)){
        # Must have already assigned.
        stopOnLine(lineNum, line, "Multiple @serializers specified for one function.")
      }

      if (!s %in% names(.globals$serializers)){
        stop("No such @serializer registered: ", s)
      }

      ser <- .globals$serializers[[s]]

      if (!is.na(serMat[1, 4]) && serMat[1,4] != ""){
        # We have an arg to pass in to the serializer
        argList <- eval(parse(text=serMat[1,4]))

        serializer <- do.call(ser, argList)
      } else {
        serializer <- ser()
      }
    }

    shortSerMat <- stringi::stri_match(line, regex="^#['\\*]\\s*@(json|html)")
    if (!is.na(shortSerMat[1,2])){
      s <- stri_trim_both(shortSerMat[1,2])
      if (!is.null(serializer)){
        # Must have already assigned.
        stopOnLine(lineNum, line, "Multiple @serializers specified for one function (shorthand serializers like @json count, too).")
      }

      if (!is.na(s) && !s %in% names(.globals$serializers)){
        stop("No such @serializer registered: ", s)
      }

      # TODO: support arguments to short serializers once they require them.
      serializer <- .globals$serializers[[s]]()
    }

    imageMat <- stringi::stri_match(line, regex="^#['\\*]\\s*@(jpeg|png)(\\s+(.*)\\s*$)?")
    if (!is.na(imageMat[1,1])){
      if (!is.null(image)){
        # Must have already assigned.
        stopOnLine(lineNum, line, "Multiple image annotations on one function.")
      }
      image <- imageMat[1,2]
    }

    responseMat <- stringi::stri_match(line, regex="^#['\\*]\\s*@response\\s+(\\w+)\\s+(\\S.+)\\s*$")
    if (!is.na(responseMat[1,1])){
      resp <- list()
      resp[[responseMat[1,2]]] <- list(description=responseMat[1,3])
      responses <- c(responses, resp)
    }

    paramMat <- stringi::stri_match(line, regex="^#['\\*]\\s*@param(\\s+([^\\s]+)(\\s+(.*))?\\s*$)?")
    if (!is.na(paramMat[1,2])){
      p <- stri_trim_both(paramMat[1,3])
      if (is.na(p) || p == ""){
        stopOnLine(lineNum, line, "No parameter specified.")
      }

      name <- paramMat[1,3]
      type <- NA

      nameType <- stringi::stri_match(name, regex="^([^\\s]+):(\\w+)(\\*?)$")
      if (!is.na(nameType[1,1])){
        name <- nameType[1,2]
        type <- plumberToSwaggerType(nameType[1,3])
        #stopOnLine(lineNum, line, "No parameter type specified")
      }


      reqd <- FALSE
      if (!is.na(nameType[1,4])){
        reqd <- nameType[1,4] == "*"
      }
      params[[name]] <- list(desc=paramMat[1,5], type=type, required=reqd)
    }

    commentMat <- stringi::stri_match(line, regex="^#['\\*]\\s*([^@\\s].*$)")
    if (!is.na(commentMat[1,2])){
      comments <- paste(comments, commentMat[1,2])
    }

    lineNum <- lineNum - 1
  }

  list(
    path = path,
    verbs = verbs,
    preempt = preempt,
    filter = filter,
    image = image,
    serializer = serializer,
    assets = assets,
    params = params,
    comments = comments,
    responses = responses
  )
}

#' Activate a "block" of code found in a plumber API.
#' @noRd
activateBlock <- function(srcref, file, e, addEndpoint, addFilter, addAssets) {
  lineNum <- srcref[1] - 1

  block <- parseBlock(lineNum, file)

  processors <- NULL
  if (!is.null(block$image) && !is.null(.globals$processors[[block$image]])){
    processors <- list(.globals$processors[[block$image]])
  } else if (!is.null(block$image)){
    stop("Image processor not found: ", block$image)
  }

  if (sum(!is.null(block$filter), !is.null(block$path), !is.null(block$assets)) > 1){
    stopOnLine(lineNum, file[lineNum], "A single function can only be a filter, an API endpoint, or an asset (@filter AND @get, @post, @assets, etc.)")
  }

  if (!is.null(block$path)){
    addEndpoint(block$verbs, block$path, e, block$serializer,
                                processors, srcref, block$preempt,
                                block$params, block$comments, block$responses)
  } else if (!is.null(block$filter)){
    addFilter(block$filter, e, block$serializer, processors, srcref)
  } else if (!is.null(block$assets)){
    addAssets(block$assets$dir, block$assets$path, e, srcref)
  }
}