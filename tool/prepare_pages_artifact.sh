#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <web-root> <artifact.tar>" >&2
  exit 64
fi

site_directory="$1"
artifact_path="$2"

for required_file in \
  "index.html" \
  "404.html" \
  ".well-known/assetlinks.json"; do
  if [[ ! -f "$site_directory/$required_file" ]]; then
    echo "Missing required Pages file: $site_directory/$required_file" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$artifact_path")"

if tar --version 2>/dev/null | grep --quiet 'bsdtar'; then
  tar \
    --create \
    --dereference \
    --file "$artifact_path" \
    --directory "$site_directory" \
    --exclude=.git \
    --exclude=.github \
    .
else
  tar \
    --create \
    --dereference \
    --hard-dereference \
    --file "$artifact_path" \
    --directory "$site_directory" \
    --exclude=.git \
    --exclude=.github \
    .
fi

if ! tar --list --file "$artifact_path" \
  | grep --fixed-strings --line-regexp \
    './.well-known/assetlinks.json' >/dev/null; then
  echo "Pages artifact does not contain .well-known/assetlinks.json" >&2
  exit 1
fi
