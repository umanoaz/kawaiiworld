#! /bin/bash
set -euo pipefail

REGISTRY="docker.io"
DOCKERHUB_USER="umanoaz"
REPO_NAME="kawaii_web"
TAG="latest"
IMAGE_NAME="${REGISTRY}/${DOCKERHUB_USER}/${REPO_NAME}:${TAG}"
CONTAINER_NAME="kawaiiworld_cnt"
BUILD_CONTEXT="/home/umanoaz/workspace/kawaiiworld/"
TOKEN_FILE="/home/umanoaz/workspace/kawaiiworld/token.txt"

echo "Authenthicating to $REGISTRY"

if [ ! -f "$TOKEN_FILE" ]; then
    echo "Error: Token file $TOKEN_FILE not found. Cannot authenticate."
    exit 1
fi
# Securely pipe the token into standard input. This avoids JSON parser errors 
# and keeps the credential hidden from the host's process tree (ps aux).
cat "$TOKEN_FILE" | podman login "$REGISTRY" --username "$DOCKERHUB_USER" --password-stdin


# Check if container exists (running or stopped) using Podman's native commands.
# This is far more resilient than parsing 'podman ps' with awk/tail.
if podman container exists "$CONTAINER_NAME"; then
    echo "Container $CONTAINER_NAME exists. Stopping and removing..."
    # Stop the container. '|| true' ensures the script doesn't fail if already stopped.
    podman stop "$CONTAINER_NAME" || true
    podman rm "$CONTAINER_NAME"
else
    echo "Container $CONTAINER_NAME not found. Proceeding with fresh creation..."
fi

# Check if the image exists, and remove it to ensure we build from scratch.
if podman image exists "$IMAGE_NAME"; then
    echo "Removing existing image $IMAGE_NAME..."
    
    # Clean up any orphaned containers from previous deployments locking the image
    ORPHANED_CONTAINERS=$(podman ps -a -q --filter "ancestor=$IMAGE_NAME")
    if [ -n "$ORPHANED_CONTAINERS" ]; then
        echo "Removing orphaned containers attached to $IMAGE_NAME..."
        # Force remove those containers so the image can be safely deleted
        podman rm -f "$ORPHANED_CONTAINERS"
    fi

    podman rmi "$IMAGE_NAME"
fi

echo "Building image..."
podman build -t "$IMAGE_NAME" "$BUILD_CONTEXT"

echo "Pushing image to $REGISTRY"
podman push "$IMAGE_NAME"

echo "Deploying container..."
# We explicitly set --name so we have a deterministic identifier for future runs.
podman run -d --name "$CONTAINER_NAME" -p 8080:80 "$IMAGE_NAME"

echo "Deployment complete. Showing initial logs:"
podman logs "$CONTAINER_NAME"
