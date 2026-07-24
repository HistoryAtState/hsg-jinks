#!/usr/bin/env sh

# Runs every time this container is (re)created -- as the devcontainer's
# postCreateCommand, or manually via `docker compose exec existdb sh
# .devcontainer/init.sh` after a plain `docker compose up` (which does NOT
# trigger postCreateCommand). See README "Container initialization (init.sh)".
#
# Everything here seeds state that lives inside eXist's own database and does
# NOT survive container recreation -- unlike the code (bind-mounted) or the
# frus-data-jinks/profile-theme-uswds baselines (baked into the image, so
# they autodeploy on every fresh boot with no help from this script).

sleep 10
cd $(dirname "$0")/..

# Without this, admin can't act on frus-data-jinks/hsg-jinks resources owned
# by the tei group/user (e.g. a later `jinks sync` writes auth errors as file
# content instead of failing loudly).
curl -s -G -u 'admin:' --data-urlencode '_query=sm:add-group-member("tei","admin")' \
    http://localhost:8080/exist/rest/db >/dev/null

ant

# repo:install-and-deploy-from-db() is unsafe to call on top of an
# already-registered package: it silently drops some files instead of
# overwriting them (observed: modules/hsg-api.xql + countries-api.xql/.json
# vanish, breaking the roaster API router with err:XQST0059). Harmless on a
# truly fresh instance (nothing registered yet), but this script can be
# re-run by hand to redeploy edited code without recreating the container --
# `xst package install` avoids the same trap by always undeploy()+remove()-
# ing first, so do the same here.
PKG_URI=$(sed -n 's/.*name="\([^"]*\)".*/\1/p' expath-pkg.xml | head -1)
curl -s -G -u 'admin:' --data-urlencode \
    "_query=if (\"$PKG_URI\" = repo:list()) then (repo:undeploy(\"$PKG_URI\"), repo:remove(\"$PKG_URI\")) else ()" \
    http://localhost:8080/exist/rest/db >/dev/null

for XAR in build/*.xar; do
    echo Installing $XAR
    curl --upload-file $XAR -u 'admin:' http://localhost:8080/exist/rest/db/system/repo/init.xar
    curl -u 'admin:' 'http://localhost:8080/exist/rest/db?_xpath=repo:install-and-deploy-from-db("/db/system/repo/init.xar")'
done