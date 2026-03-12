#!/bin/bash
# Fix PROD sync issue - regenerate genesis and restart

set -e

echo "Stopping all containers..."
docker-compose down

echo "Cleaning chaindata..."
docker volume rm xdc-gp5-xinfinorg || true

echo "Restarting with fresh sync..."
docker-compose up -d

echo "Monitoring sync for 30 seconds..."
sleep 30
docker logs xdc-node-geth-pr5 --tail 20
