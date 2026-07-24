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
for XAR in build/*.xar; do
    echo Installing $XAR
    curl --upload-file $XAR -u 'admin:' http://localhost:8080/exist/rest/db/system/repo/init.xar
    curl -u 'admin:' 'http://localhost:8080/exist/rest/db?_xpath=repo:install-and-deploy-from-db("/db/system/repo/init.xar")'
done