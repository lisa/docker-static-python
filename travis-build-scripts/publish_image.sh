#!/bin/bash
# Tags and publishes to Docker Hub

set +x

REPO="thedoh/static-python"

if [[ -z $TRAVIS_BRANCH ]]; then
  echo "Undefined TRAVIS_BRANCH. Can't safely publish image because we don't know what version was used. Aborting."
  exit 1
fi

echo "Changing directory to $(dirname $0)/.."
cd "$(dirname $0)/.."

if [[ -z $DOCKER_PASS ]]; then
  echo "Don't know the docker password. Aborting."
  exit 1
fi

echo $DOCKER_PASS | docker login -u=$DOCKER_USER --password-stdin
if [[ $? -ne 0 ]]; then
  echo "Could not log in to Docker Hub (Exit: $?). Aborting."
  exit 1
fi

# If this is from a merge to master then it should be tagged 'latest'
if [[ $TRAVIS_BRANCH == "master" ]]; then
  # What version did we just build? It's hard to tell since the branch name
  # doesn't contain it.
  base_version=$(grep '^ARG PYTHON_BASE_VERSION=' Dockerfile | head -n1 | cut -d '=' -f 2)
  rc_version=$(grep '^ARG PYTHON_RC=' Dockerfile | head -n1 | cut -d '=' -f 2)
  if [[ -z $base_version ]]; then
    echo "Couldn't determine the software version from the Dockerfile, so, aborting."
    exit 1
  fi
  comboversion="${base_version}${rc_version}"
  docker tag $REPO:$TRAVIS_COMMIT $REPO:latest
  docker tag $REPO:$TRAVIS_COMMIT $REPO:$comboversion
else
  # version came from the branch name
  docker tag $REPO:$TRAVIS_COMMIT $REPO:$TRAVIS_BRANCH  
fi

# Don't push the commit hash
docker rmi $REPO:$TRAVIS_COMMIT
docker push $REPO
