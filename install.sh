#!/bin/sh
#
# Cortex one-line installer.
#
#   curl -fsSL https://raw.githubusercontent.com/bkrabach/cortex-releases/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/bkrabach/cortex-releases/main/install.sh | sh -s -- --yes
#
# This file is hosted in the PUBLIC bkrabach/cortex-releases repo and fetched
# with zero authentication, so it is deliberately small and asks for nothing
# of its own: no keys, no personal data, no machine-specific paths. Anything
# after `--` is passed straight through to `cortex init`.
#
# What it does, in order:
#   1. installs uv (the Python packager Cortex ships through), if missing
#   2. checks that you can actually read the private Cortex source repos --
#      and if not, names the wall (an unauthenticated/uninvited GitHub
#      account) and the one-line fix, instead of letting the install fail
#      later with a 404 that reads exactly like a typo
#   3. installs the cortex-hub CLI
#   4. hands off to `cortex init`, which stands the whole stack up and, on a
#      real run, finishes by having Cortex answer you
#
# Nothing here needs sudo. `cortex init` asks for the two provider keys it
# needs and names anything only a person can supply.

set -eu

# The published home of the CLI. A git+ URL because the repo is private --
# which is exactly why step 2 checks read access to it before relying on it.
HUB_REPO_URL="https://github.com/bkrabach/cortex-hub"
HUB_INSTALL_SOURCE="git+https://github.com/bkrabach/cortex-hub"

say() { printf '%s\n' "$*"; }
fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

# --------------------------------------------------------------------------
# 1. uv -- installed only if it is missing. Installing a package manager
#    behind your back without saying so is not something to do quietly.
# --------------------------------------------------------------------------
ensure_uv() {
    if command -v uv >/dev/null 2>&1; then
        say "uv: already installed ($(command -v uv))"
        return
    fi
    say "uv: not found -- installing it from https://astral.sh/uv"
    curl -fsSL https://astral.sh/uv/install.sh | sh
    # uv installs to ~/.local/bin; make it usable in THIS shell without a
    # re-login.
    export PATH="$HOME/.local/bin:$PATH"
    command -v uv >/dev/null 2>&1 || fail \
        "uv was installed but is not on PATH -- open a new shell (or add \
\$HOME/.local/bin to PATH) and re-run this installer"
}

# --------------------------------------------------------------------------
# 2. Can you actually read the private Cortex repos? Unauthenticated, `uv
#    tool install git+https://...` fails with a 404 that reads exactly like a
#    typo -- so check first, non-interactively, and name the real wall.
#
#    Prefers `gh auth status` when gh is on PATH; otherwise falls back to a
#    read-only `git ls-remote`. Either way this must never hang waiting on an
#    interactive credential prompt, so GIT_TERMINAL_PROMPT=0 and (when
#    available) a short `timeout` bound the fallback check.
# --------------------------------------------------------------------------
can_read_hub_repo() {
    if command -v gh >/dev/null 2>&1; then
        gh auth status >/dev/null 2>&1
        return
    fi
    if command -v timeout >/dev/null 2>&1; then
        GIT_TERMINAL_PROMPT=0 timeout 10 git ls-remote "$HUB_REPO_URL" HEAD \
            >/dev/null 2>&1
        return
    fi
    GIT_TERMINAL_PROMPT=0 git ls-remote "$HUB_REPO_URL" HEAD >/dev/null 2>&1
}

ensure_git_access() {
    command -v git >/dev/null 2>&1 || fail \
        "git is not installed -- install it first (e.g. 'sudo apt-get install git')"

    say "git: checking read access to the Cortex source repos ..."
    if can_read_hub_repo; then
        say "git: access confirmed"
        return
    fi

    cat >&2 <<EOF
error: cannot read ${HUB_REPO_URL}

  Wall 1: the Cortex source repos are private. Run:

      gh auth login

  (or set up git credentials some other way), then re-run this script.
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
    uv tool install --force "$HUB_INSTALL_SOURCE"

    command -v cortex >/dev/null 2>&1 || fail \
        "cortex-hub installed but 'cortex' is not on PATH -- uv usually puts it \
in \$HOME/.local/bin; add that to PATH and run 'cortex init'"

    say "cortex init: standing the stack up"
    exec cortex init "$@"
}

main "$@"
