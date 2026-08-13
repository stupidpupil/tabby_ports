#!/usr/bin/env bash
#
# Idempotently:
#   1. Clones (or fast-forward updates) stupidpupil/tabby_ports
#   2. Chowns the checkout to macports:macports
#   3. Registers it as a MacPorts source in sources.conf
#
# Run with: sudo ./setup-tabby-ports.sh
#
# Written for macOS (BSD userland). Deliberately avoids GNU-only flags
# (stat -c, getent, etc.) since that's the only place this ever runs.

set -euo pipefail

REPO_URL="https://github.com/stupidpupil/tabby_ports.git"
REPO_DIR="/opt/local/var/macports/github.com/stupidpupil/tabby_ports"
SOURCES_CONF="/opt/local/etc/macports/sources.conf"
SOURCE_LINE="file://$REPO_DIR"
OWNER_USER="macports"
OWNER_GROUP="macports"

if [[ "${EUID}" -ne 0 ]]; then
    echo "error: this script must be run as root (e.g. via sudo)" >&2
    exit 1
fi

if ! command -v git &>/dev/null; then
    echo "error: git not found (install Xcode Command Line Tools: xcode-select --install)" >&2
    exit 1
fi

# --- 0. Validate the target owner up front, before touching anything ----
# (macOS has no getent(1); dscl is the native way to query directory services.)

if ! id -u "${OWNER_USER}" &>/dev/null; then
    echo "error: user '${OWNER_USER}' does not exist on this system" >&2
    exit 1
fi
if ! dscl . -read "/Groups/${OWNER_GROUP}" &>/dev/null; then
    echo "error: group '${OWNER_GROUP}' does not exist on this system" >&2
    exit 1
fi

# --- 1. Clone or update the repo ----------------------------------------

if [[ -d "${REPO_DIR}/.git" ]]; then
    echo "==> ${REPO_DIR} already a git checkout; pulling updates"
    if ! git -C "${REPO_DIR}" pull --quiet --ff-only; then
        echo "error: ${REPO_DIR} could not be fast-forwarded (local changes/divergence?)" >&2
        echo "       resolve manually, then re-run this script" >&2
        exit 1
    fi
elif [[ -e "${REPO_DIR}" ]]; then
    if [[ -d "${REPO_DIR}" && -z "$(ls -A "${REPO_DIR}" 2>/dev/null)" ]]; then
        echo "==> ${REPO_DIR} exists but is empty; cloning into it"
        git clone --quiet "${REPO_URL}" "${REPO_DIR}"
    else
        echo "error: ${REPO_DIR} exists, is non-empty, and is not a git checkout" >&2
        echo "       refusing to overwrite it" >&2
        exit 1
    fi
else
    echo "==> cloning ${REPO_URL} to ${REPO_DIR}"
    mkdir -p "$(dirname "${REPO_DIR}")"
    git clone --quiet "${REPO_URL}" "${REPO_DIR}"
fi

# --- 2. Fix ownership -----------------------------------------------------

echo "==> chown -R ${OWNER_USER}:${OWNER_GROUP} ${REPO_DIR}"
chown -R "${OWNER_USER}:${OWNER_GROUP}" "${REPO_DIR}"

# --- 3. Register the source in sources.conf --------------------------------

if [[ ! -f "${SOURCES_CONF}" ]]; then
    echo "error: ${SOURCES_CONF} not found" >&2
    exit 1
fi

if grep -qxF "${SOURCE_LINE}" "${SOURCES_CONF}"; then
    echo "==> ${SOURCES_CONF} already contains the source entry; leaving as is"
else
    echo "==> adding source entry to ${SOURCES_CONF}"
    tmpfile="$(mktemp "${TMPDIR:-/tmp}/sources.conf.XXXXXXXXXX")"
    trap 'rm -f "${tmpfile}"' EXIT

    # Insert just above the first rsync:// line (local sources take
    # priority over the main tree), or append at the end if there isn't
    # one. Routing both cases through awk also normalizes a missing
    # trailing newline on the original file, which a raw `>>` append
    # would otherwise silently corrupt.
    awk -v line="${SOURCE_LINE}" '
        !inserted && /^rsync:\/\// { print line; inserted = 1 }
        { print }
        END { if (!inserted) print line }
    ' "${SOURCES_CONF}" > "${tmpfile}"

    # Write into the existing file (rather than mv/install over it) so
    # the destination keeps its original inode, permissions, and owner
    # -- no need to capture/reapply mode bits with stat, which also
    # sidesteps the BSD-stat-vs-GNU-stat flag mismatch entirely.
    cat "${tmpfile}" > "${SOURCES_CONF}"
fi

echo "==> done. Run 'sudo port selfupdate' to sync/index the new source."
