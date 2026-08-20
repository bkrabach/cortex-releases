#!/usr/bin/env bash
#
# Cortex one-line installer.
#
#   curl -fsSL <this-script-url> | sh
#   curl -fsSL <this-script-url> | sh -s -- --yes --use-shell-keys
#
# Anything after `--` is passed straight through to `cortex init`, so the same
# flags that command takes work here too.
#
# What it does, in order:
#   1. install uv (the Python packager Cortex ships through) if it is missing
#   2. check that git can actually READ the private Cortex repos -- and if not,
#      name the wall (unaccepted GitHub invitations) and the one-line fix
#   3. `uv tool install` the cortex-hub CLI
#   4. exec `cortex init "$@"` -- which stands the whole stack up and, on a real
#      run, bootstraps the brain and finishes by having Cortex answer you
#
# It installs nothing that needs sudo and asks for no keys of its own; `cortex
# init` handles all of that, and names anything only a human can supply.

set -eu

# The published home of the CLI. A git+ URL because the repo is private -- which
# is exactly why step 2 checks git can read it before we lean on it here.
HUB_REPO_URL="https://github.com/bkrabach/cortex-hub"
HUB_INSTALL_SOURCE="git+https://github.com/bkrabach/cortex-hub"

say()  { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------
# 1. uv -- installed only if it is missing. Installing a package manager behind
#    someone's back is not something to do silently, so this says it is doing it.
# --------------------------------------------------------------------------
ensure_uv() {
    if command -v uv >/dev/null 2>&1; then
        say "uv: already installed ($(command -v uv))"
        return
    fi
    say "uv: not found -- installing it from https://astral.sh/uv"
    curl -fsSL https://astral.sh/uv/install.sh | sh
    # uv installs to ~/.local/bin; make it usable in THIS shell without a
    # re-login, the same hint the manual instructions give.
    export PATH="$HOME/.local/bin:$PATH"
    command -v uv >/dev/null 2>&1 || fail \
        "uv was installed but is not on PATH -- open a new shell (or add \
\$HOME/.local/bin to PATH) and re-run this installer"
}

# --------------------------------------------------------------------------
# 2. git credential reachability. Every Cortex repo is private. Unauthenticated,
#    `uv tool install git+https://...` fails with a 404 that reads exactly like a
#    typo -- so probe it first with a fast read-only ls-remote and, on failure,
#    name the actual wall and its fix instead of letting uv fail opaquely later.
# --------------------------------------------------------------------------
ensure_git_access() {
    command -v git >/dev/null 2>&1 || fail \
        "git is not installed -- install it first (e.g. 'sudo apt-get install git')"

    say "git: checking read access to the private Cortex repos ..."
    if GIT_TERMINAL_PROMPT=0 git ls-remote "$HUB_REPO_URL" HEAD >/dev/null 2>&1; then
        say "git: can read ${HUB_REPO_URL}"
        return
    fi

    cat >&2 <<EOF
error: git cannot read ${HUB_REPO_URL}

  All Cortex repos are private. This reads the same whether you are not logged
  in, or logged in but not yet invited -- so fix both, in order:

    1. Authenticate git to GitHub:
         gh auth login          # GitHub.com -> HTTPS -> browser/device
         gh auth setup-git
       (no gh? configure any git credential helper holding a token instead.)

    2. If it still cannot read the repo, that is Wall 1: an unaccepted GitHub
       invitation. Accept the pending invites to the Cortex repos, then re-run.

  Re-run this installer once the command above prints a sha, not a 404:
       git ls-remote ${HUB_REPO_URL} HEAD
EOF
    exit 1
}

# --------------------------------------------------------------------------
# 3 + 4. install the CLI, then hand straight off to `cortex init`.
# --------------------------------------------------------------------------
main() {
    ensure_uv
    ensure_git_access

    say "cortex-hub: installing the CLI ..."
    uv tool install "$HUB_INSTALL_SOURCE"

    command -v cortex >/dev/null 2>&1 || fail \
        "cortex-hub installed but 'cortex' is not on PATH -- uv usually puts it \
in \$HOME/.local/bin; add that to PATH and run 'cortex init'"

    say "cortex init: standing the stack up (passing through: $*)"
    exec cortex init "$@"
}

main "$@"
