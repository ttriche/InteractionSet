###############################################################
# Defines the GInteractions class, to hold interacting coordinates. 

setClass("GInteractions", 
    contains="Vector",
    representation(
        anchor1="integer",
        anchor2="integer",
        regions="GRanges",
        NAMES="characterORNULL"
    ),
    prototype(
        anchor1=integer(0),
        anchor2=integer(0),
        regions=GRanges(),
        NAMES=NULL
    )
)

# Could inherit from Hits with an extra 'regions'; but I don't want to
# deal with 'queryHits' and 'subjectHits', which would get very confusing
# when you're dealing with queries and subjects in the overlap section.

.check_inputs <- function(anchor1, anchor2, regions, same.length=TRUE) {
    if (!all(is.finite(anchor1)) || !all(is.finite(anchor2))) { 
        return("all anchor indices must be finite integers")
    }
    if (!all(anchor1 >= 1L) || !all(anchor2 >= 1L)) {
        return('all anchor indices must be positive integers')
    } 
    nregs <- length(regions)
    if ( !all(anchor1 <= nregs) || !all(anchor2 <= nregs)) {
        return("all anchor indices must refer to entries in 'regions'")
    } 
    if (same.length && length(anchor1)!=length(anchor2)) { 
        return("first and second anchor vectors have different lengths")
    }
    return(TRUE)
}

setValidity2("GInteractions", function(object) {
    if (is.unsorted(object@regions)) { # Don't move into .check_inputs, as resorting comes after checking validity in various methods.
        return("'regions' should be sorted")
    }
    msg <- .check_inputs(object@anchor1, object@anchor2, object@regions)
    if (is.character(msg)) { return(msg) }

    ### Length of anchors versus object is automatically checked by 'parallelSlotNames.'

    if (!is.null(object@NAMES)) {
        if (length(object@NAMES)!=length(object)) {
            stop("'NAMES' must be NULL or have length equal to that of the object")
        }
    }

    return(TRUE)
})

setMethod("parallelSlotNames", "GInteractions", function(x) {
    c("anchor1", "anchor2", callNextMethod())         
})

scat <- function(fmt, vals=character(), exdent=2, ...) {
    vals <- ifelse(nzchar(vals), vals, "''")
    lbls <- paste(S4Vectors:::selectSome(vals), collapse=" ")
    txt <- sprintf(fmt, length(vals), lbls)
    cat(strwrap(txt, exdent=exdent, ...), sep="\n")
}

setMethod("show", signature("GInteractions"), function(object) {
    cat("class:", class(object), "\n")
    cat("length:", length(object@anchor1), "\n")

    my.names <- object@NAMES
    if (!is.null(my.names)) scat("names(%d): %s\n", my.names)
    else scat("names: NULL\n")
    
    expt <- names(metadata(object))
    if (is.null(expt))
        expt <- character(length(metadata(object)))
    scat("metadata(%d): %s\n", expt)

    mcolnames <- names(mcols(object))
    fmt <- "metadata column names(%d): %s\n"
    scat(fmt, mcolnames)
    
    cat("regions:", length(object@regions), "\n")
})

###############################################################
# Ordered equivalents, where swap state is enforced.

setClass("StrictGInteractions", contains="GInteractions")
setValidity2("StrictGInteractions", function(object) {
    if (any(object@anchor1 < object@anchor2)) { 
        stop("'anchor1' cannot be less than 'anchor2'")
    }
    return(TRUE)
})

###############################################################
# Constructors

.enforce_order <- function(anchor1, anchor2) {
    swap <- anchor2 < anchor1
    if (any(swap)) { 
        temp <- anchor1[swap]
        anchor1[swap] <- anchor2[swap]
        anchor2[swap] <- temp
    }
    return(list(anchor1=anchor1, anchor2=anchor2))
}

.resort_regions <- function(anchor1, anchor2, regions) {
    if (is.unsorted(regions)) { 
        o <- order(regions)
        new.pos <- seq_along(o)
        new.pos[o] <- new.pos
        anchor1 <- new.pos[anchor1]
        anchor2 <- new.pos[anchor2]
        regions <- regions[o]
    }
    return(list(anchor1=anchor1, anchor2=anchor2, regions=regions)) 
}

.new_GInteractions <- function(anchor1, anchor2, regions, metadata, mode=c("normal", "strict")) {
    mode <- match.arg(mode)
    elementMetadata <- new("DataFrame", nrows=length(anchor1))

    # Checking odds and ends.
    anchor1 <- as.integer(anchor1)
    anchor2 <- as.integer(anchor2)
    msg <- .check_inputs(anchor1, anchor2, regions)
    if (is.character(msg)) { stop(msg) }

    out <- .resort_regions(anchor1, anchor2, regions)
    anchor1 <- out$anchor1
    anchor2 <- out$anchor2
    regions <- out$regions

    # Checking what the mode should be.
    if (mode=="normal") {
        cls <- "GInteractions"
    } else {
        cls <- "StrictGInteractions"
        out <- .enforce_order(anchor1, anchor2)
        anchor1 <- out$anchor2 # Flipped on purpose. 
        anchor2 <- out$anchor1
    }

    new(cls, 
        anchor1=anchor1,
        anchor2=anchor2,
        regions=regions,
        elementMetadata=elementMetadata,
        metadata=as.list(metadata))
}

setGeneric("GInteractions", function(anchor1, anchor2, regions, ...) { standardGeneric("GInteractions") })
setMethod("GInteractions", c("numeric", "numeric", "GRanges"), 
    function(anchor1, anchor2, regions, metadata=list(), mode="normal") {
        .new_GInteractions(anchor1, anchor2, regions=regions, metadata=metadata, mode=mode)
})

.collate_GRanges <- function(...) {
    incoming <- list(...)
    obj.dex <- rep(factor(seq_along(incoming)), lengths(incoming))
    combined <- do.call(c, incoming)
    refdex <- seq_along(combined)
    
    # Sorting and re-indexing.
    o <- order(combined)
    new.pos <- seq_along(combined)
    new.pos[o] <- new.pos
    refdex <- new.pos[refdex]
    combined <- combined[o]

    # Removing duplicates and re-indexing.
    is.first <- !duplicated(combined)
    new.pos <- cumsum(is.first)
    combined <- combined[is.first]
    refdex <- new.pos[refdex]    
    return(list(indices=split(refdex, obj.dex), ranges=combined))
}

setMethod("GInteractions", c("GRanges", "GRanges", "GenomicRangesORmissing"), 
    function(anchor1, anchor2, regions, metadata=list(), mode="normal") {
        # Stripping metadata and putting it somewhere else.
        mcol1 <- mcols(anchor1)
        mcols(anchor1) <- NULL
        colnames(mcol1) <- sprintf("anchor1.%s", colnames(mcol1))
        mcol2 <- mcols(anchor2)
        mcols(anchor2) <- NULL
        colnames(mcol2) <- sprintf("anchor2.%s", colnames(mcol2))

        if (missing(regions)) {
            # Making unique regions to save space (metadata is ignored)
            collated <- .collate_GRanges(anchor1, anchor2)
            regions <- collated$ranges
            anchor1 <- collated$indices[[1]]
            anchor2 <- collated$indices[[2]]
        } else {
            anchor1 <- match(anchor1, regions)
            anchor2 <- match(anchor2, regions)
            if (any(is.na(anchor1)) || any(is.na(anchor2))) {
                stop("anchor regions missing in specified 'regions'")
            }
        }

        out <- .new_GInteractions(anchor1=anchor1, anchor2=anchor2, 
            regions=regions, metadata=metadata, mode=mode)
        mcols(out) <- DataFrame(mcol1, mcol2)
        out
   }
)

setMethod("GInteractions", c("missing", "missing", "GenomicRangesORmissing"),
    function(anchor1, anchor2, regions, metadata=list(), mode="normal") {
        if (missing(regions)) { regions <- GRanges() }
        .new_GInteractions(integer(0), integer(0), regions, metadata, mode=mode)
})

###############################################################
# Subsetting. Mostly automatically taken care of by extractROWS from Vector
# with new parallel slots of anchor1 and anchor2, but we need to handle NAMES.

setMethod("extractROWS", "GInteractions", function(x, i) {
    if (!is.null(x@NAMES)) { 
        x@NAMES <- extractROWS(names(x), i)
    }
    callNextMethod()
})

###############################################################
# Combining

setMethod("rbind", "GInteractions", function(..., deparse.level=1) {
    args <- unname(list(...))
    ans <- args[[1]]
    all.regions <- lapply(args, FUN=regions)
    all.anchor1 <- lapply(args, FUN=slot, name="anchor1")
    all.anchor2 <- lapply(args, FUN=slot, name="anchor2")
    all.mcols <- lapply(args, FUN=mcols)

    # Checking if regions are the same; collating if not.
    if (length(unique(all.regions))!=1L) { 
        collated <- do.call(.collate_GRanges, all.regions)
        ans@regions <- collated$ranges       
        for (i in seq_along(all.regions)) {
            all.anchor1[[i]] <- collated$indices[[i]][all.anchor1[[i]]]
            all.anchor2[[i]] <- collated$indices[[i]][all.anchor2[[i]]]
        }
    }

    ans@anchor1 <- unlist(all.anchor1)
    ans@anchor2 <- unlist(all.anchor2)
    ans@elementMetadata <- do.call(rbind, all.mcols)

    # Checking what to do with names.
    all.names <- lapply(args, FUN=names)
    unnamed <- sapply(all.names, is.null)
    if (!all(unnamed)) { 
        for (u in which(unnamed)) {
            all.names[[u]] <- character(length(args[[u]]))
        }
        ans@NAMES <- unlist(all.names)
    }
    return(ans)
})

setMethod("c", "GInteractions", function(x, ..., recursive=FALSE) { # synonym for 'rbind'.
    rbind(x, ...)                   
})

###############################################################
# Other methods

setMethod("order", "GInteractions", function(..., na.last=TRUE, decreasing=FALSE) {
    all.ids <- unlist(lapply(list(...), anchors, id=TRUE), recursive=FALSE)
    do.call(order, c(all.ids, list(na.last=na.last, decreasing=decreasing)))
})

setMethod("duplicated", "GInteractions", function(x, incomparables=FALSE, fromLast=FALSE, ...) 
# Stable sort required here: first entry in 'x' is always non-duplicate if fromLast=FALSE,
# and last entry is non-duplicate if fromLast=TRUE.
{
    if (!nrow(x)) { return(logical(0)) }
    a1 <- anchors(x, id=TRUE, type="first")
    a2 <- anchors(x, id=TRUE, type="second")
    o <- order(a1, a2) 
    if (fromLast) { o <- rev(o) }
    is.dup <- c(FALSE, diff(a1[o])==0L & diff(a2[o])==0L)
    is.dup[o] <- is.dup
    return(is.dup)
})

setMethod("as.data.frame", "GInteractions", function (x, row.names=NULL, optional=FALSE, ...) {
    all1 <- anchors(x, type="first", id=TRUE)
    all2 <- anchors(x, type="second", id=TRUE)
    used <- logical(length(regions(x)))
    used[all1] <- TRUE
    used[all2] <- TRUE
    new.index <- cumsum(used) # Accelerate by only converting what we need.

    regs.dframe <- as.data.frame(regions(x)[used], optional=optional, ...)
    a1.dframe <- regs.dframe[new.index[all1],]
    a2.dframe <- regs.dframe[new.index[all2],]
    if (missing(row.names)) { row.names <- names(x) }
    data.frame(anchor1=a1.dframe, anchor2=a2.dframe, mcols(x), row.names=row.names, ...)
})

###############################################################
# End
