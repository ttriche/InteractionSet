###############################################################
# Defines the GInteractions class, to hold interacting coordinates. 

setClass("GInteractions", 
    contains="Vector",
    representation(
        anchor1="integer",
        anchor2="integer",
        regions="GRanges"
    ),
    prototype(
        anchor1=integer(0),
        anchor2=integer(0),
        regions=GRanges()
    )
)

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

setValidity("GInteractions", function(object) {
    if (is.unsorted(object@regions)) { # Don't move into .check_inputs, as resorting comes after checking validity in various methods.
        return("'regions' should be sorted")
    }
    msg <- .check_inputs(object@anchor1, object@anchor2, object@regions)
    if (is.character(msg)) { return(msg) }

    if (nrow(object@elementMetadata)!=length(object@anchor1)) { 
        return("'elementMetadata' nrow must be equal to number of interactions")
    }
    if (!all(object@anchor1 >= object@anchor2)) { 
        return('first anchors cannot be less than the second anchor')
    }
    return(TRUE)
})

setMethod("show", signature("GInteractions"), function(object) {
    cat("class:", class(object), "\n")
    cat("pairs:", length(object@anchor1), "\n")
    cat(sprintf("regions: %i\n", length(object@regions)))
    # Need to add elementMetadata, metadata return values.
})

###############################################################
# Constructors

.enforce_order <- function(anchor1, anchor2) {
    swap <- anchor2 > anchor1
    if (any(swap)) { 
        temp <- anchor1[swap]
        anchor1[swap] <- anchor2[swap]
        anchor2[swap] <- temp
    }
    return(list(anchor1=anchor1, anchor2=anchor2))   
}

.resort_regions <- function(anchor1, anchor2, regions, enforce.order=TRUE) {
    if (is.unsorted(regions)) { 
        o <- order(regions)
        new.pos <- seq_along(o)
        new.pos[o] <- new.pos
        anchor1 <- new.pos[anchor1]
        anchor2 <- new.pos[anchor2]
        regions <- regions[o]
    }
    if (enforce.order) { 
        out <- .enforce_order(anchor1, anchor2)
        anchor1 <- out$anchor1
        anchor2 <- out$anchor2
    }
    return(list(anchor1=anchor1, anchor2=anchor2, regions=regions)) 
}

.new_GInteractions <- function(anchor1, anchor2, regions, metadata) {
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

    new("GInteractions", 
        anchor1=anchor1,
        anchor2=anchor2,
        regions=regions,
        elementMetadata=elementMetadata,
        metadata=as.list(metadata))
}

setGeneric("GInteractions", function(anchor1, anchor2, ...) { standardGeneric("GInteractions") })
setMethod("GInteractions", c("numeric", "numeric"), 
    function(anchor1, anchor2, regions, metadata=list()) {
        .new_GInteractions(anchor1, anchor2, regions=regions, metadata=metadata)
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

setMethod("GInteractions", c("GRanges", "GRanges"), 
    function(anchor1, anchor2, regions, metadata=list()) {

        # Making unique regions to save space (metadata is ignored)
        if (missing(regions)) {
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

       .new_GInteractions(anchor1=anchor1, anchor2=anchor2, 
            regions=regions, metadata=metadata)
   }
)

setMethod("GInteractions", c("missing", "missing"),
    function(anchor1, anchor2, regions=GRanges(), metadata=list()) {
        .new_GInteractions(integer(0), integer(0), regions, metadata)
})

###############################################################
# Subsetting

setMethod("[", c("GInteractions", "ANY"), function(x, i, j, ..., drop=TRUE) {
    a1 <- x@anchor1[i]
    a2 <- x@anchor2[i]
    ans <- callNextMethod()
    ans@anchor1 <- a1
    ans@anchor2 <- a2
    return(ans)
})

setMethod("subset", "GInteractions", function(x, i) {
    x[i]
})

###############################################################
# Combining

setMethod("rbind", "GInteractions", function(..., deparse.level=1) {
    args <- unname(list(...))
    ans <- args[[1]]
    all1 <- list(anchors(ans, type="first", id=TRUE))
    all2 <- list(anchors(ans, type="second", id=TRUE))
    em <- list(mcols(ans))

    for (x in args[-1]) { 
        if (!identical(regions(x), regions(ans))) { stop("regions must be identical in 'rbind'") }
        all1 <- c(all1, anchors(x, type="first", id=TRUE))
        all2 <- c(all2, anchors(x, type="second", id=TRUE))
        em <- c(em, mcols(x))
    }

    ans@anchor1 <- unlist(all1)
    ans@anchor2 <- unlist(all2)
    elementMetadata(ans) <- do.call(rbind, em)
    return(ans)
})

# "c" is slightly different from "rbind", in that it allows different regions to be combined.
setMethod("c", "GInteractions", function(x, ..., recursive = FALSE) {
    incoming <- list(x, ...)
    all.regions <- lapply(incoming, FUN=regions)
    collated <- do.call(.collate_GRanges, all.regions)

    for (i in seq_along(incoming)) {
        cur.anchors <- anchors(incoming[[i]], id=TRUE)
        incoming[[i]]@regions <- collated$ranges
        anchors(incoming[[i]]) <- list(collated$indices[[i]][cur.anchors$first],
                                       collated$indices[[i]][cur.anchors$second])
    }

    do.call(rbind, incoming)
})

###############################################################
# Other methods

setMethod("order", "GInteractions", function(..., na.last=TRUE, decreasing=FALSE) {
    all.ids <- unlist(lapply(list(...), anchors, id=TRUE), recursive=FALSE)
    do.call(order, c(all.ids, list(na.last=na.last, decreasing=decreasing)))
})

setMethod("sort", "GInteractions", function(x, decreasing=FALSE, ...) {
    x[order(x, decreasing=decreasing),]
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

setMethod("unique", "GInteractions", function(x, incomparables=FALSE, fromLast=FALSE, ...) {
    x[!duplicated(x, incomparables=incomparables, fromLast=fromLast, ...),]
})

# Not sure how much sense it makes to provide GRanges methods on the GInteractions,
# as these'll be operating on 'regions' rather than 'anchors'.
#setMethod("seqinfo", "GInteractions", function(x) {
#     seqinfo(x@regions)
#})
#
#setReplaceMethod("seqinfo", "GInteractions", function(x, value) {
#    seqinfo(x@regions) <- value
#    validObject(x)
#    return(x)
#})

setMethod("split", "GInteractions", function(x, f, drop=FALSE, ...) {
    splitAsList(x, f, drop=drop)
})

###############################################################
# End