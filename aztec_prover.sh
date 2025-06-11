#!/bin/bash

# ======================
# 🛠 AZTEC PROVER - FULL DEPLOYMENT
# ======================

# ---------- Defaults ----------
IMAGE="aztecprotocol/aztec:0.87.8"
NETWORK="alpha-testnet"
DATA_DIR="/root/aztec-prover"
P2P_PORT="40400"
API_PORT="8080"

# ---------- Validations ----------
validate_ip() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "❌ Invalid IP: $1"; exit 1
  }
}

validate_url() {
  [[ "$1" =~ ^https?:// ]] || {
    echo "❌ Invalid URL: $1"; exit 1
  }
}

# ---------- User Input ----------
clear
echo "========================================"
echo "🔧 AZTEC PROVER DEPLOYMENT WIZARD"
echo "========================================"

read -p "👉 Enter WAN IP (e.g., 111.123.456.789): " WAN_IP
validate_ip "$WAN_IP"

read -p "👉 Enter Sepolia RPC URL: " RPC_SEPOLIA
validate_url "$RPC_SEPOLIA"

read -p "👉 Enter Beacon API URL: " BEACON_SEPOLIA
validate_url "$BEACON_SEPOLIA"

read -p "👉 Enter Publisher Private Key: " PRIVATE_KEY
[ -z "$PRIVATE_KEY" ] && { echo "❌ Private Key required"; exit 1; }

read -p "👉 Enter Prover ID: " PROVER_ID
[ -z "$PROVER_ID" ] && { echo "❌ Prover ID required"; exit 1; }

read -p "👉 Number of agents (≥1): " AGENT_COUNT
[[ "$AGENT_COUNT" =~ ^[0-9]+$ ]] && [ "$AGENT_COUNT" -ge 1 ] || {
  echo "❌ Invalid agent count"; exit 1
}

# ---------- Generate docker-compose.yml ----------
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  prover-node:
    image: $IMAGE
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start
      --prover-node --archiver --network $NETWORK'
    depends_on:
      broker:
        condition: service_started
        required: true
    environment:
      PROVER_COORDINATION_NODE_URL: "http://$WAN_IP:$API_PORT"
      P2P_IP: "$WAN_IP"
      P2P_ANNOUNCE_ADDRESSES: "/ip4/$WAN_IP/tcp/$P2P_PORT"
      ETHEREUM_HOSTS: "$RPC_SEPOLIA"
      L1_CONSENSUS_HOST_URLS: "$BEACON_SEPOLIA"
      PROVER_PUBLISHER_PRIVATE_KEY: "$PRIVATE_KEY"
      PROVER_ENABLED: "true"
      P2P_ENABLED: "true"
      P2P_TCP_PORT: "$P2P_PORT"
      P2P_UDP_PORT: "$P2P_PORT"
      DATA_STORE_MAP_SIZE_KB: "134217728"
      LOG_LEVEL: "debug"
      PROVER_BROKER_HOST: "http://broker:$API_PORT"
    ports:
      - "$API_PORT:$API_PORT"
      - "$P2P_PORT:$P2P_PORT"
      - "$P2P_PORT:$P2P_PORT/udp"
    volumes:
      - $DATA_DIR/node:/data

  broker:
    image: $IMAGE
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start
      --prover-broker --network $NETWORK'
    environment:
      DATA_DIRECTORY: /data
      ETHEREUM_HOSTS: "$RPC_SEPOLIA"
      LOG_LEVEL: "debug"
    volumes:
      - $DATA_DIR/broker:/data
EOF

# ---------- Add Agents ----------
for i in $(seq 1 $AGENT_COUNT); do
  cat >> docker-compose.yml <<EOF

  agent-$i:
    image: $IMAGE
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start
      --prover-agent --network $NETWORK'
    environment:
      PROVER_ID: "$PROVER_ID"
      PROVER_BROKER_HOST: "http://broker:$API_PORT"
      PROVER_AGENT_POLL_INTERVAL_MS: "10000"
    depends_on:
      - broker
    restart: unless-stopped
EOF
done

# ---------- Deployment ----------
docker compose up -d

# ---------- Output ----------
echo ""
echo "========================================"
echo "🎉 DEPLOYMENT COMPLETE"
echo "========================================"
echo "📌 Prover Node: http://$WAN_IP:$API_PORT"
echo "📌 P2P Address: /ip4/$WAN_IP/tcp/$P2P_PORT"
echo "📌 Agents Running: $AGENT_COUNT"
echo "🔍 Check status: docker ps -a"
echo "📜 View logs: docker compose logs -f"
