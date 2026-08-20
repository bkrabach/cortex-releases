#!/usr/bin/env bash
#
# Cortex one-line installer.
#
#   curl -fsSL <this-script-url> | sh
#   curl -fsSL <this-script-url> | sh -s -- --yes
#
# Anything after `--` is passed straight through to `cortex init`, so the same
# flags that command takes work here too.
#
# What it does, in order:
#   0. adopt the provider keys you already have exported. A piped `curl | sh`
#      inherits your shell environment, so if the two keys Cortex needs are
#      already exported it hands them to `cortex init` to SAVE (--use-shell-keys)
#      -- and if a needed one is missing it stops HERE, before installing
#      anything, and names the exact export(s) to run
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

# Set to 1 by ensure_provider_keys when it finds usable keys in the shell that
# `cortex init` should be told to save.
USE_SHELL_KEYS=0

say()  { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --------------------------------------------------------------------------
# 0. Provider keys -- finish the job, or stop friendly BEFORE installing.
#
# Cortex needs two keys, for two different processes:
#   GATEWAY (voice & chat)  -- OPENAI_API_KEY or XAI_API_KEY
#   BRAIN   (what it thinks) -- ANTHROPIC_API_KEY ONLY
# A bare OPENAI/XAI export satisfies the GATEWAY but NOT the brain: the
# installed brain provider module is anthropic-only (cortex_hub/paths.py's
# AGENT_PROVIDER_MODULE), so an openai/xai-only brain would answer "No
# providers available" to every message forever -- nothing was ever
# installed that could mount that key. A grok/xai-only brain is a SEPARATE,
# unsupported path (FRESH-INSTALL.md); this gate does not pretend otherwise.
#
# A piped `curl ... | sh` inherits these exports, but the gateway and brain run
# as their OWN services and never see the installer's shell -- so when both keys
# are present we hand `cortex init` --use-shell-keys, which copies them to the
# files/env those services actually read. When a needed key is absent we stop
# right here (nothing installed yet) and name the exact export to run.
# --------------------------------------------------------------------------

# True when the caller is already supplying keys some other way. Those paths
# (--*-key, --*-key-file, --use-shell-keys) belong to `cortex init`, so the
# shell gate below must defer to it rather than second-guess the command line.
caller_supplies_keys() {
    for a in "$@"; do
        case "$a" in
        --use-shell-keys | \
            --openai-key | --openai-key-file | \
            --xai-key | --xai-key-file | \
            --anthropic-key | --anthropic-key-file | \
            --brain-key | --brain-key-file)
            return 0
            ;;
        --openai-key=* | --openai-key-file=* | \
            --xai-key=* | --xai-key-file=* | \
            --anthropic-key=* | --anthropic-key-file=* | \
            --brain-key=* | --brain-key-file=*)
            return 0
            ;;
        esac
    done
    return 1
}

ensure_provider_keys() {
    if caller_supplies_keys "$@"; then
        return
    fi

    # The provider keys actually exported, for the plain-language report.
    found=""
    for pair in \
        "OPENAI_API_KEY=${OPENAI_API_KEY:-}" \
        "XAI_API_KEY=${XAI_API_KEY:-}" \
        "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}"; do
        name=${pair%%=*}
        value=${pair#*=}
        if [ -n "$value" ]; then
            if [ -n "$found" ]; then found="$found, $name"; else found="$name"; fi
        fi
    done

    # Which gateway-capable key is exported? (mints voice/chat)
    gateway_key=""
    if [ -n "${OPENAI_API_KEY:-}" ]; then
        gateway_key="OPENAI_API_KEY"
    elif [ -n "${XAI_API_KEY:-}" ]; then
        gateway_key="XAI_API_KEY"
    fi

    # Which brain-capable key is exported? ANTHROPIC ONLY -- the installed
    # brain provider module (cortex_hub/paths.py's AGENT_PROVIDER_MODULE) is
    # anthropic-only. A bare OPENAI/XAI export mints gateway sessions fine
    # but cannot make the BRAIN think: no module was ever installed that
    # could mount it, so it would answer "No providers available" forever.
    # A grok/xai-only brain is a separate, unsupported path
    # (FRESH-INSTALL.md) -- this gate does not pretend otherwise.
    brain_key=""
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        brain_key="ANTHROPIC_API_KEY"
    fi

    if [ -n "$gateway_key" ] && [ -n "$brain_key" ]; then
        USE_SHELL_KEYS=1
        say "keys: found $found in your shell"
        say "      Cortex will save them for its services (--use-shell-keys) -- the"
        say "      gateway and brain run as their own services and cannot read your"
        say "      shell, so the keys are copied to the files/env they DO read."
        return
    fi

    # A needed key is missing. Stop BEFORE installing anything and name the fix.
    {
        printf '%s\n' "error: Cortex needs two provider keys and cannot find them in your shell."
        printf '%s\n' ""
        printf '%s\n' "  A piped 'curl ... | sh' inherits the keys you exported, and Cortex runs"
        printf '%s\n' "  two things that each need one:"
        printf '%s\n' "    - the GATEWAY (voice & chat)   needs  OPENAI_API_KEY   (or XAI_API_KEY)"
        printf '%s\n' "    - the BRAIN   (what it thinks)  needs  ANTHROPIC_API_KEY (OPENAI/XAI do NOT"
        printf '%s\n' "      satisfy it -- the installed brain provider module is anthropic-only)"
        printf '%s\n' ""
        if [ -n "$found" ]; then
            printf '%s\n' "  Found in your shell: $found"
        else
            printf '%s\n' "  Found in your shell: none"
        fi
        printf '%s\n' ""
        printf '%s\n' "  Export the missing key(s), then run this same one-liner again:"
        printf '%s\n' ""
        if [ -z "$gateway_key" ]; then
            printf '%s\n' "    export OPENAI_API_KEY=sk-...          # the gateway (xAI: XAI_API_KEY=xai-...)"
        fi
        if [ -z "$brain_key" ]; then
            printf '%s\n' "    export ANTHROPIC_API_KEY=sk-ant-...   # the brain"
        fi
        printf '%s\n' ""
        printf '%s\n' "  Nothing has been installed."
    } >&2
    exit 1
}

# True if --use-shell-keys is already among the caller's args -- so we never
# hand `cortex init` the same flag twice.
args_have_use_shell_keys() {
    for a in "$@"; do
        if [ "$a" = "--use-shell-keys" ]; then
            return 0
        fi
    done
    return 1
}

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
    # Capture what the USER passed, before we add anything of our own -- the
    # "passing through" line reports the caller's args, never our injected flag.
    user_arg_count=$#
    user_args="$*"

    ensure_provider_keys "$@"
    ensure_uv
    ensure_git_access

    say "cortex-hub: installing the CLI ..."
    uv tool install "$HUB_INSTALL_SOURCE"

    command -v cortex >/dev/null 2>&1 || fail \
        "cortex-hub installed but 'cortex' is not on PATH -- uv usually puts it \
in \$HOME/.local/bin; add that to PATH and run 'cortex init'"

    # Hand the shell keys to init to SAVE, unless the caller already asked.
    if [ "$USE_SHELL_KEYS" = "1" ] && ! args_have_use_shell_keys "$@"; then
        set -- --use-shell-keys "$@"
    fi

    if [ "$user_arg_count" -gt 0 ]; then
        say "cortex init: standing the stack up (passing through: $user_args)"
    else
        say "cortex init: standing the stack up"
    fi
    exec cortex init "$@"
}

main "$@"
