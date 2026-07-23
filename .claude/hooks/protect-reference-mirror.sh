#!/bin/sh
# PreToolUse hook (Bash tool): protect the hsg-shell reference mirror.
#
# Host port 8080 is the READ-ONLY old-site mirror (docker container
# hsg-shell-test) that every worktree compares against. It must never be
# written to -- no xst package install, no jinks, no REST writes. This hook
# blocks Bash commands that address host port 8080 with anything write-shaped;
# plain reads (curl GET, xst ls/get) stay allowed.
#
# Registered in .claude/settings.json, so every worktree inherits it via git.

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# Only commands that address host port 8080 concern us.
echo "$cmd" | grep -qiE '(localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0):8080' || exit 0

# Inside a container, localhost:8080 is that worktree's OWN eXist (init.sh
# legitimately installs xars there) -- allow exec'd commands.
echo "$cmd" | grep -qE '(docker|devcontainer)([[:space:]]+compose)?[[:space:]]+exec' && exit 0

if echo "$cmd" | grep -qiE -- \
  '-X[[:space:]]*(PUT|POST|DELETE|PATCH)|--upload-file|--data(-[a-z]+)?([[:space:]=]|$)|--form|-[A-Za-z]*[TdF]([[:space:]]|$)|xst[[:space:]]+(up|upload|rm|edit|package|deploy|execute)|jinks[[:space:]]+(create|update|sync|watch|run)'; then
    cat >&2 <<'EOF'
BLOCKED: host port 8080 is the READ-ONLY hsg-shell reference mirror (container
hsg-shell-test). Writing to it would poison the comparison baseline for every
worktree. Use this worktree's own eXist instance instead -- its host port is in
./.env (EXISTDB_SERVER). Reads (plain curl GET, xst ls/get) remain allowed.
EOF
    exit 2
fi
exit 0
