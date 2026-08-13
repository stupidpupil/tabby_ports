#!/usr/bin/env bash

ISO8601_REGEXP="(20[[:digit:]]{2}-[01][[:digit:]]-[0-3][[:digit:]]{1})"
CHANGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR)

VERSION_REGEXP="version([[:space:]]+)(.+)"
REVISION_REGEXP="revision([[:space:]]+)([0-9]+)"

if [[ -z $CHANGED_FILES ]]; then
  exit 0
fi

while IFS= read -r line ; do

  PORTFILE_PATH="$line"

  if [[ $(basename "$PORTFILE_PATH") != "Portfile" ]]; then
    continue
  fi

  PORTDIR_PATH=$(dirname "$PORTFILE_PATH")

  echo "$(tput bold)$PORTDIR_PATH $(tput sgr0)"

  PORT_LINT_FAILED=0
  PORT_LINT_OUTPUT=$(port lint -q "$PORTDIR_PATH" 2>&1)

  if [[ -z "$PORT_LINT_OUTPUT" ]]; then
    echo " - passed port lint ✔"
  else
    PORT_LINT_FAILED="$(($PORT_LINT_FAILED+1))"
    echo " - failed port lint ❌"
    echo "${PORT_LINT_OUTPUT/^/   /}"
  fi

  CURR_VERSION=$(sed -n -E "s/$VERSION_REGEXP/\2/p" "$PORTFILE_PATH")

  if echo "$CURR_VERSION" | grep -E "$ISO8601_REGEXP" > /dev/null 2>&1; then
    NEW_VERSION=$(date -I)
    sed -E -e "s/version([[:space:]]+)$CURR_VERSION/version\1$NEW_VERSION/g" -i "" "$PORTFILE_PATH"

    if [[ "$CURR_VERSION" != "$NEW_VERSION" ]]; then
      CURR_VERSION="$NEW_VERSION"
      git add "$PORTFILE_PATH"
      echo " - updated version to $NEW_VERSION 🗓️"
    fi
  fi

  if git show HEAD~1:"$PORTFILE_PATH" > /dev/null 2>&1 ; then
    OLD_VERSION=$(git show HEAD~1:"$PORTFILE_PATH" | sed -n -E "s/$VERSION_REGEXP/\2/p")

    if [[ "$OLD_VERSION" = "$CURR_VERSION" ]]; then
      OLD_REVISION=$(git show HEAD~1:"$PORTFILE_PATH" | sed -n -E "s/$REVISION_REGEXP/\2/p")
      NEW_REVISION="$(($OLD_REVISION+1))"
    else
      NEW_REVISION="0"
    fi
    
    if sed -E -e "s/$REVISION_REGEXP/revision\1$NEW_REVISION/g" -i "" "$PORTFILE_PATH"; then
      git add "$PORTFILE_PATH"
      echo " - updated revision to $NEW_REVISION ✨"
    fi
  fi

  printf "\n"
done <<< "$CHANGED_FILES"

if [[ $PORT_LINT_FAILED -gt 0 ]]; then
  exit 1
fi
