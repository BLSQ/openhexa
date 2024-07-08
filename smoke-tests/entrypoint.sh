#!/bin/bash

# Check if the correct number of arguments are provided
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <url> <username> <password>"
  exit 1
fi

# Assign arguments to variables
OPENHEXA_BASE_URL=$1
OPENHEXA_USERNAME=$2
OPENHEXA_PASSWORD=$3

# Export the variables to be accessible in the test scripts
export OPENHEXA_BASE_URL
export OPENHEXA_USERNAME
export OPENHEXA_PASSWORD

# Navigate to the directory containing the tests
cd /code


# Print the environment
echo "Launching smoke tests on $OPENHEXA_BASE_URL..."

# Run the Playwright tests
npx playwright test

# Capture the exit status of the tests
EXIT_STATUS=$?

# Exit with the same status as the Playwright tests
exit $EXIT_STATUS