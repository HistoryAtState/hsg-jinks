#!/usr/bin/env sh

# Runs every time this container is (re)created -- as the devcontainer's
# postCreateCommand, or manually via `docker compose exec existdb sh
# .devcontainer/init.sh` after a plain `docker compose up` (which does NOT
# trigger postCreateCommand). CI runs it on the runner against the published
# container port. See README "Container initialization (init.sh)".
#
# Everything here seeds state that lives inside eXist's own database and does
# NOT survive container recreation -- unlike the code (bind-mounted) or what
# the image carries (data, libraries, generator, theme).

set -e

sleep 10
cd $(dirname "$0")/..

# xst talks to the eXist on port 8080. Exported values win over the
# worktree's .env, which holds the host port.
export EXISTDB_SERVER=http://localhost:8080/exist EXISTDB_USER=admin EXISTDB_PASS=

# Without this, admin can't act on frus-data-jinks/hsg-jinks resources owned
# by the tei group/user (e.g. a later `jinks sync` writes auth errors as file
# content instead of failing loudly).
xst run 'sm:add-group-member("tei","admin")' >/dev/null

ant

# Replaces any installed hsg-jinks, including the one the base image ships.
# --force: the version number stays 1.0.0 between builds. xst undeploys and
# removes the old registration first; repo:install-and-deploy-from-db() on
# top of a registered package silently drops files (observed: the roaster API
# modules vanish, err:XQST0059).
xst package install --force build/*.xar
