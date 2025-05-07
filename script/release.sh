#!/bin/bash

# Check if email argument is provided
if [ -z "$1" ]; then
    echo "Error: Email address is required"
    echo "Usage: $0 'firstname lastname <email@address.org>'"
    exit 1
fi

# Build the Docker image
docker build -t openhexa-release -f Dockerfile.release .

# Run the dch command in the container
docker run --rm -v "$(pwd):/work" -e "EMAIL=$1" openhexa-release dch -rD stable