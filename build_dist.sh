#!/bin/bash
set -e

# Build the docker image, stopping at the build-step
docker build --target build-step -t fripan-builder .

# Create a temporary container
CONTAINER_ID=$(docker create fripan-builder)

# Create dist directory
mkdir -p dist

# Copy assets
echo "Copying assets to dist/..."
docker cp $CONTAINER_ID:/app/build.js dist/
docker cp $CONTAINER_ID:/app/pan.html dist/
docker cp $CONTAINER_ID:/app/index.html dist/
docker cp $CONTAINER_ID:/app/pan.index dist/
docker cp $CONTAINER_ID:/app/test.descriptions dist/
docker cp $CONTAINER_ID:/app/test.proteinortho dist/
docker cp $CONTAINER_ID:/app/test.strains dist/
docker cp $CONTAINER_ID:/app/test.roary dist/pan.roary

# Copy css if it exists in src, though it might be bundled.
# The original Makefile copies it, so we will too to be safe.
docker cp $CONTAINER_ID:/app/src/pan.css dist/

# Cleanup
docker rm $CONTAINER_ID

echo "Build complete! Assets are in dist/"
