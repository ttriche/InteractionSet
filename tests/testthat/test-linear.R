# Testing the linearize function for InteractionSet objects.

set.seed(200)
N <- 50
all.starts <- round(runif(N, 1, 100))
all.ends <- all.starts + round(runif(N, 5, 20))
all.regions <- GRanges(rep(c("chrA", "chrB"), c(N-10, 10)), IRanges(all.starts, all.ends))
all.regions <- unique(all.regions)
N <- length(all.regions)

Np <- 100
all.anchor1 <- sample(N, Np, replace=TRUE)
all.anchor2 <- sample(N, Np, replace=TRUE)
Nlibs <- 4
counts <- matrix(rpois(Np*Nlibs, lambda=10), ncol=Nlibs)
colnames(counts) <- seq_len(Nlibs)
x <- InteractionSet(counts, GInteractions(all.anchor1, all.anchor2, all.regions))

o <- order(all.regions)
new.regions <- all.regions[o]
new.pos <- integer(length(o))
new.pos[o] <- seq_along(new.pos)
new.anchor1 <- new.pos[all.anchor1]
new.anchor2 <- new.pos[all.anchor2]

# Running through all possibilities:

for (interest in seq_len(N)) {
    cur.reg <- regions(x)[interest]
    out <- linearize(x, interest)
    chosen <- new.anchor1==interest | new.anchor2==interest
    expect_that(assay(out), is_identical_to(assay(x[chosen,])))
    expect_output(show(out), sprintf("class: RangedSummarizedExperiment 
dim: %i 4 
metadata(0):
assays(1): ''
rownames: NULL
rowData names(0):
colnames(4): 1 2 3 4
colData names(0):", sum(chosen)), fixed=TRUE)

    new.ranges <- anchors(x, type="first")
    not1 <- new.ranges!=cur.reg
    new.ranges[!not1] <- anchors(x, type="second")[!not1]
    new.ranges <- new.ranges[chosen]
    expect_that(rowRanges(out), is_identical_to(new.ranges))

    # Comparing with equivalent GRanges method.
    out2 <- linearize(x, cur.reg, type="equal")
    expect_that(out, equals(out2))
}

# What happens with silly inputs?

expect_that(nrow(linearize(x, 0)), is_identical_to(0L))
expect_that(nrow(linearize(x[0,], 1)), is_identical_to(0L))
expect_that(nrow(suppressWarnings(linearize(x, GRanges("chrC", IRanges(1,1))))), is_identical_to(0L))
lenA <- max(end(regions(x)[seqnames(regions(x))=="chrA"]))
expect_warning(linearize(x, GRanges("chrA", IRanges(1, lenA))), "multiple matching reference regions, using the first region only")
