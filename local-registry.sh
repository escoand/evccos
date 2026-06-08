#!/bin/sh

set -e

LOCALREGISTRY=127.0.0.1:5000
IMAGES="
    docker.io/evcc/evcc:latest
    docker.io/tailscale/tailscale:latest
"

docker run \
    --detach \
    --name registry \
    --publish "${LOCALREGISTRY%*:}:5000" \
    --replace \
    registry

for IMAGE in $IMAGES; do
    docker pull "$IMAGE"
    docker tag "$IMAGE" "$LOCALREGISTRY/${IMAGE#*/}"
    docker push --tls-verify=false "$LOCALREGISTRY/${IMAGE#*/}"
done