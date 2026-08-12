# syntax=docker/dockerfile:1

# Pinned R + mgcv reference environment ("oracle") for validating Polaris RE.
#
# Two independent things must be pinned for outputs to be reproducible:
#   1. the base image  -> by digest, because the :4.6.1 tag is periodically
#      rebuilt and therefore moves
#   2. the CRAN repo   -> by dated snapshot, because rocker/r-ver ships
#      CRAN=https://p3m.dev/cran/__linux__/noble/latest, which does NOT pin
#      package versions

ARG R_VERSION=4.6.1
ARG BASE_DIGEST=sha256:555a0e7734b17f3901f01c8e379f87d797a0e6344a4cc3b246329ed3f0689809

FROM rocker/r-ver:${R_VERSION}@${BASE_DIGEST}

# Globals declared before FROM must be re-declared to be visible in the stage.
ARG R_VERSION
ARG BASE_DIGEST
ARG CRAN_SNAPSHOT=2026-08-01

# Build identity. Supplied by CI; defaulted to "unknown" so a local `docker build`
# still works and is visibly unidentified rather than falsely stamped.
ARG IMAGE_TAG=unknown
ARG BUILD_NUMBER=0
ARG BUILD_CREATED=unknown
ARG SOURCE_REVISION=unknown
ARG SOURCE_REPO=https://github.com/jonathancrawford05/R-Gam-base

ENV BASE_IMAGE_DIGEST=${BASE_DIGEST} \
    CRAN_SNAPSHOT=${CRAN_SNAPSHOT} \
    CRAN=https://p3m.dev/cran/__linux__/noble/${CRAN_SNAPSHOT}

# setup_R.sh baked the "latest" repo URL into Rprofile.site when the base image
# was built, so setting $CRAN alone is not enough. Rprofile.site is evaluated
# top to bottom, so an appended options(repos=) wins over the baked-in one.
# The __linux__/noble prefix serves prebuilt binaries; the HTTPUserAgent that
# unlocks them is already set by the base image.
RUN printf "options(repos = c(CRAN = '%s'))\n" "${CRAN}" >> "${R_HOME}/etc/Rprofile.site" \
    && R -q -e "cat(getOption('repos')[['CRAN']], '\n')"

# mgcv is already present as a recommended package, but install it explicitly so
# its version is a deliberate choice pinned by CRAN_SNAPSHOT rather than an
# accident of which R release the base image happens to be built from.
#
# mboost brings its own tree (stabs, nnls, quadprog, partykit, survival, ...),
# resolved by the same dated snapshot rather than from HEAD. Note that this is
# where a dependency could drag Matrix or nlme forward underneath mgcv, which is
# what assert-pinned-versions.R below exists to catch.
#
# install.packages() only warns on failure, so assert loadability separately.
RUN R -q -e "install.packages(c('mgcv', 'jsonlite', 'digest', 'sessioninfo', 'mboost'))" \
    && R -q -e "p <- c('mgcv','jsonlite','digest','sessioninfo','mboost'); \
                ok <- vapply(p, requireNamespace, logical(1), quietly = TRUE); \
                if (!all(ok)) stop('failed to install: ', paste(p[!ok], collapse=', '))"

COPY oracle/ /opt/oracle/
COPY scripts/build-manifest.R /opt/oracle/build-manifest.R
COPY scripts/assert-pinned-versions.R /opt/oracle/assert-pinned-versions.R

# Fails the build if adding a package moved mgcv or anything it links against.
RUN Rscript /opt/oracle/assert-pinned-versions.R

# Fails the build if mboost cannot fit the shape of model it was added for, so a
# broken install stops here rather than at the first user.
RUN Rscript /opt/oracle/mboost_smoke.R

# Freeze the resolved versions into the image. Every reference output embeds
# this block, so "which mgcv produced this number" is answerable from the
# artifact alone.
RUN Rscript /opt/oracle/build-manifest.R /opt/oracle/manifest.json \
    && ln -sf /opt/oracle/manifest.json /opt/versions.json \
    && cat /opt/oracle/manifest.json

# The build-identity manifest, at the fixed path a consumer reads:
#   docker run --rm <image> cat /opt/oracle-manifest.json
# Versions come from the installed library, so it records what IS here rather
# than what was asked for.
#
# This is ADDITIVE. /opt/versions.json deliberately still points at
# /opt/oracle/manifest.json above, because the two files are different schemas:
# v2 drops r_svn_rev and moves built_at under `image`. Re-pointing the alias
# would leave an existing reader's `.built_at` silently null -- a path that stays
# truthful-looking while what it denotes changes underneath, which is precisely
# the failure this repo's tag policy exists to prevent.
COPY scripts/oracle-manifest.R /opt/oracle/oracle-manifest.R
RUN IMAGE_TAG="${IMAGE_TAG}" BUILD_NUMBER="${BUILD_NUMBER}" \
    BUILD_CREATED="${BUILD_CREATED}" SOURCE_REVISION="${SOURCE_REVISION}" \
    SOURCE_REPO="${SOURCE_REPO}" \
    Rscript /opt/oracle/oracle-manifest.R /opt/oracle-manifest.json \
    && cat /opt/oracle-manifest.json

ENV ORACLE_HOME=/opt/oracle
WORKDIR /work

# `docker inspect` alone should answer "what is this", without pulling the
# filesystem or knowing anything about the image's internals.
ARG IMAGE_DESCRIPTION="Digest-pinned R + mgcv + mboost reference environment producing independent GAM outputs for validating Polaris RE."
LABEL org.opencontainers.image.source="${SOURCE_REPO}" \
      org.opencontainers.image.version="${IMAGE_TAG}" \
      org.opencontainers.image.created="${BUILD_CREATED}" \
      org.opencontainers.image.revision="${SOURCE_REVISION}" \
      org.opencontainers.image.description="${IMAGE_DESCRIPTION}" \
      org.opencontainers.image.licenses="MIT" \
      io.polaris.r-version="${R_VERSION}" \
      io.polaris.cran-snapshot="${CRAN_SNAPSHOT}" \
      io.polaris.build-number="${BUILD_NUMBER}" \
      io.polaris.base-digest="${BASE_DIGEST}"

CMD ["R"]
