#!/bin/sh
# Build emit-run from this directory.
set -e
cd "$(dirname "$0")"
cc -arch arm64 -O2 -fobjc-arc -framework AppKit -o emit-run emit-run.m
echo "Built ./emit-run"
echo "Run: ./emit-run [--headless] /path/to/64EMIT02.img"
