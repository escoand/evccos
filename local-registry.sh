#!/bin/sh

set -e

LOCALREGISTRY=127.0.0.1:5000

docker run \
    --detach \
    --name registry \
    --publish "${LOCALREGISTRY%*:}:5000" \
    --replace \
    registry

find filesystem -name "*.container" -exec grep -h ^Image= {} + |
tr -d '\r' |
while IFS="=" read -r _ IMAGE; do
    docker pull "$IMAGE"
    docker tag "$IMAGE" "$LOCALREGISTRY/${IMAGE#*/}"
    docker push --tls-verify=false "$LOCALREGISTRY/${IMAGE#*/}"
done