#!/bin/sh
set -e

echo "==> Building images container..."
docker build -f Dockerfile.images -t amazon-edge-images .

echo "==> Building videos container..."
docker build -f Dockerfile.videos -t amazon-edge-videos .

echo "==> Stopping any existing containers..."
docker rm -f amazon-edge-images amazon-edge-videos 2>/dev/null || true

echo "==> Starting images container on port 8080..."
docker run -d --name amazon-edge-images -p 8080:80 amazon-edge-images

echo "==> Starting videos container on port 8081..."
docker run -d --name amazon-edge-videos -p 8081:80 amazon-edge-videos

echo ""
echo "Images: http://localhost:8080"
echo "Videos: http://localhost:8081"
echo ""
echo "To stop: docker rm -f amazon-edge-images amazon-edge-videos"
