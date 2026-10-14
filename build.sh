#!/bin/zsh
# Builds the app and installs assets into ~/.maltipoo-local
set -e
cd "$(dirname "$0")"
H=~/.maltipoo-local; mkdir -p $H
cp -R gifs gifs_orig dur.json $H/
swiftc -O -target arm64-apple-macos12.0 dog.swift -o $H/dog
echo "Built $H/dog — run it, then grant Accessibility (needed for double-Cmd)."
