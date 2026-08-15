#!/usr/bin/env bash

set -euo pipefail

ISO8601_REGEXP="^(20[[:digit:]]{2}-[01][[:digit:]]-[0-3][[:digit:]]{1})$"
CHANGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR)

VERSION_REGEXP="^version([[:space:]]+)(.+)$"
REVISION_REGEXP="^revision([[:space:]]+)([0-9]+)"

if [[ -z "$CHANGED_FILES" ]]; then
  exit 0
fi

# tput errors (and prints usage noise) when there's no controlling
# terminal / TERM, which is common for hooks invoked by GUI git clients.
# Resolve the escape sequences once, falling back to empty strings.
if [[ -t 1 ]] && BOLD=$(tput bold 2>/dev/null) && RESET=$(tput sgr0 2>/dev/null); then
  :
else
  BOLD=""
  RESET=""
fi

PORT_LINT_FAILED=0

while IFS= read -r line ; do

  PORTFILE_PATH="$line"

  if [[ $(basename "$PORTFILE_PATH") != "Portfile" ]]; then
    continue
  fi

  PORTDIR_PATH=$(dirname "$PORTFILE_PATH")

  echo "${BOLD}${PORTDIR_PATH} ${RESET}"

  # `port lint` exits non-zero on lint failures -- that's the expected,
  # handled case here, not a script error, so it needs `|| true`: under
  # `set -e` a bare assignment's exit status is that of the command
  # substitution inside it, and without the guard the hook would abort
  # right here on the first lint warning, before ever reporting it.
  PORT_LINT_OUTPUT=$(port lint -q "$PORTDIR_PATH" 2>&1) || true

  if [[ -z "$PORT_LINT_OUTPUT" ]]; then
    echo " - passed port lint ✔"
  else
    PORT_LINT_FAILED="$(($PORT_LINT_FAILED+1))"
    echo " - failed port lint ❌"
    echo "$PORT_LINT_OUTPUT" | sed 's/^/   /'
  fi

  CURR_VERSION=$(sed -n -E "s/$VERSION_REGEXP/\2/p" "$PORTFILE_PATH")

  if echo "$CURR_VERSION" | grep -E "$ISO8601_REGEXP" > /dev/null 2>&1; then
    NEW_VERSION=$(date -I)

    if [[ "$CURR_VERSION" != "$NEW_VERSION" ]]; then
      sed -E -e "s/^version([[:space:]]+)$CURR_VERSION\$/version\1$NEW_VERSION/g" -i "" "$PORTFILE_PATH"
      CURR_VERSION="$NEW_VERSION"
      git add "$PORTFILE_PATH"
      echo " - updated version to $NEW_VERSION 🗓️"
    fi
  fi

  # NB: at pre-commit time HEAD is still the commit-in-progress's parent
  # (the commit object doesn't exist yet), so the comparison baseline is
  # HEAD, not HEAD~1.
  if OLD_CONTENT=$(git show HEAD:"$PORTFILE_PATH" 2>/dev/null); then
    OLD_VERSION=$(sed -n -E "s/$VERSION_REGEXP/\2/p" <<< "$OLD_CONTENT")

    if [[ "$OLD_VERSION" = "$CURR_VERSION" ]]; then
      OLD_REVISION=$(sed -n -E "s/$REVISION_REGEXP/\2/p" <<< "$OLD_CONTENT")
      NEW_REVISION="$((10#${OLD_REVISION:-0}+1))"
    else
      NEW_REVISION="0"
    fi

    # sed exits 0 whether or not the pattern matched, so check the line
    # actually exists before claiming success / staging the file.
    if grep -qE "$REVISION_REGEXP" "$PORTFILE_PATH"; then
      sed -E -e "s/$REVISION_REGEXP.*/revision\1$NEW_REVISION/g" -i "" "$PORTFILE_PATH"
      git add "$PORTFILE_PATH"
      echo " - updated revision to $NEW_REVISION ✨"
    else
      echo " - no revision line found to update ⚠️"
    fi
  fi

  printf "\n"
done <<< "$CHANGED_FILES"

if [[ $PORT_LINT_FAILED -gt 0 ]]; then
  exit 1
fi
