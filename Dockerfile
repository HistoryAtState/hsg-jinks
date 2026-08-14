ARG EXIST_VERSION=6.4.0
ARG BUILD=local

# Library versions are pinned to the same baseline as the devcontainer
# (.devcontainer/docker-compose.yml, README "Pinned baseline") so this image
# runs exactly the stack the Cypress suite is green against. Bump both files
# together.
ARG ROUTER_VERSION=1.12.2
ARG PUBLISHER_LIB_VERSION=6.1.0
ARG JINKS_TEMPLATES_VERSION=1.4.2
ARG CAROUSEL_VERSION=0.11.10

# START STAGE 1: build the hsg-jinks app xar from this checkout
FROM ghcr.io/eeditiones/builder:latest AS builder

WORKDIR /tmp

# Build app inside container
COPY . hsg-jinks/
RUN cd hsg-jinks \
    && ant


FROM duncdrum/existdb:${EXIST_VERSION} AS build_local

ARG USR=root
USER ${USR}

ONBUILD COPY --from=builder /tmp/hsg-jinks/build/*.xar /exist/autodeploy/006.xar

# TODO(DP): Tagging scheme add EXIST_VERSION to the tag
FROM ghcr.io/jinntec/base:main AS build_prod

# NOTE the start URL http://localhost:8081/exist/apps/hsg-jinks/index.html
ARG PUBLISHER_VERSION

ARG USR=nonroot
USER ${USR}

# This assumes that a local xar file is present for building production images
ONBUILD COPY --chown=${USR} ./build/*.xar /exist/autodeploy/006.xar

FROM build_${BUILD}

ARG USR
USER ${USR:-root}

WORKDIR /exist

# EXPATH library dependencies. roaster, jinks-templates and tei-publisher-lib
# are declared in expath-pkg.xml; carousel backs the landing-page carousel
# (modules/templates/hsg-landing.xqm). eXist autodeploys alphabetically, so
# 003-005 install before the app (006) and the data packages after it.
ARG ROUTER_VERSION
ARG JINKS_TEMPLATES_VERSION
ARG PUBLISHER_LIB_VERSION
ARG CAROUSEL_VERSION
ADD --chown=${USR:-root} https://exist-db.org/exist/apps/public-repo/public/roaster-${ROUTER_VERSION}.xar /exist/autodeploy/003.xar
ADD --chown=${USR:-root} https://exist-db.org/exist/apps/public-repo/public/jinks-templates-${JINKS_TEMPLATES_VERSION}.xar /exist/autodeploy/004.xar
ADD --chown=${USR:-root} https://exist-db.org/exist/apps/public-repo/public/tei-publisher-lib-${PUBLISHER_LIB_VERSION}.xar /exist/autodeploy/005.xar
ADD --chown=${USR:-root} https://github.com/HistoryAtState/carousel/releases/download/v${CAROUSEL_VERSION}/carousel.xar /exist/autodeploy/carousel.xar

# All 11 external HistoryAtState data packages (README "External data
# packages"): countries (rdcr, wwdai), departmenthistory (gsh,
# other-publications, pocom, travels, visits), milestones, about's HAC
# documents (hac), conferences and tags. Each always tracks its repo's LATEST
# GitHub release (decision 2026-08-07: no data package stays pinned; when a
# count-style test breaks on a refresh, fix the test per "Cypress assertions
# on data-package counts" in CLAUDE.md, don't pin the data).
ADD --chown=${USR:-root} https://github.com/HistoryAtState/conferences/releases/latest/download/conferences.xar /exist/autodeploy/conferences.xar
ADD --chown=${USR:-root} https://github.com/HistoryAtState/gsh/releases/latest/download/gsh.xar /exist/autodeploy/gsh.xar
ADD --chown=${USR:-root} https://github.com/HistoryAtState/hac/releases/latest/download/hac.xar /exist/autodeploy/hac.xar
ADD --chown=${USR:-root} https://github.com/HistoryAtState/milestones/releases/latest/download/milestones.xar /exist/autodeploy/milestones.xar
ADD --chown=${USR:-root} https://github.com/HistoryAtState/other-publications/releases/latest/download/other-publications.xar /exist/autodeploy/other-publications.xar
ADD --chown=${USR:-root} https://github.com/HistoryAtState/pocom/releases/latest/download/pocom.xar /exist/autodeploy/pocom.xar
ADD --chown=${USR:-root} https://github.com/HistoryAtState/rdcr/releases/latest/download/rdcr.xar /exist/autodeploy/rdcr.xar
ADD --chown=${USR:-root} https://github.com/HistoryAtState/tags/releases/latest/download/tags.xar /exist/autodeploy/tags.xar
ADD --chown=${USR:-root} https://github.com/HistoryAtState/travels/releases/latest/download/travels.xar /exist/autodeploy/travels.xar
ADD --chown=${USR:-root} https://github.com/HistoryAtState/visits/releases/latest/download/visits.xar /exist/autodeploy/visits.xar
ADD --chown=${USR:-root} https://github.com/HistoryAtState/wwdai/releases/latest/download/wwdai.xar /exist/autodeploy/wwdai.xar

# frus-data-jinks (built from the private hsg-jinks-data repo, which has no
# GitHub release yet) must be staged at the repo root before building:
#   cp ~/.config/hsg/xars/frus-data-jinks-baseline.xar ./frus-data-jinks-0.2.xar
# or build a fresh one: cd ../../hsg-jinks-data && ant && cp build/*.xar <here>.
# The zzzz- prefix makes it autodeploy last, as in .devcontainer/Dockerfile.dev.
# Once a release exists, switch this to an ADD like the packages above.
COPY --chown=${USR:-root} frus-data-jinks-*.xar /exist/autodeploy/zzzz-frus-data-jinks.xar

# ARG ADMIN_PASS=none

ARG CACHE_MEM
ARG MAX_BROKER
ARG JVM_MAX_RAM_PERCENTAGE

# External ports: HTTP on 8081, HTTPS on 8444. Jetty reads the jetty.port /
# jetty.ssl.port system properties set below, so the container itself listens
# on these ports; run it with a matching mapping:
#   docker run -d -p 8081:8081 -p 8444:8444 <image>
ARG HTTP_PORT=8081
ARG HTTPS_PORT=8444

ARG NER_ENDPOINT=http://localhost:8001
ARG CONTEXT_PATH=auto
ARG PROXY_CACHING=false

ENV JDK_JAVA_OPTIONS="\
    -Djetty.port=${HTTP_PORT} \
    -Djetty.ssl.port=${HTTPS_PORT} \
    -Dteipublisher.ner-endpoint=${NER_ENDPOINT} \
    -Dteipublisher.context-path=${CONTEXT_PATH} \
    -Dteipublisher.proxy-caching=${PROXY_CACHING}"

# pre-populate the database by launching it once and change default pw
RUN [ "java", "org.exist.start.Main", "client", "--no-gui",  "-l", "-u", "admin", "-P", "" ]

# The build_local base image ships a HEALTHCHECK probing eXist's default
# XML-RPC port; jetty listens on 8081 here, so re-point it. Exec form can't
# expand ${HTTP_PORT} -- keep the port in sync with the ARG above.
HEALTHCHECK CMD [ "java", "org.exist.start.Main", "client", "--no-gui", "--user", "guest", "--password", "guest", "--xpath", "system:get-version()", "-ouri=xmldb:exist://localhost:8081/exist/xmlrpc" ]

EXPOSE ${HTTP_PORT} ${HTTPS_PORT}
