#!/bin/bash

# ======================
# 🛠 AZTEC PROVER - FULL DEPLOYMENT
# ======================

# ---------- Defaults ----------
IMAGE="aztecprotocol/aztec:0.87.8"
NETWORK="alpha-testnet"
DATA_DIR="/home/diszell2008/aztec-prover"
P2P_PORT="40400"
API_PORT="8080"
ENV_FILE=".env"

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

validate_number() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] || {
    echo "❌ Invalid number: $1"; exit 1
  }
}

# ---------- Check Dependencies ----------
if ! command -v curl -4 &> /dev/null; then
  echo "❌ Yêu cầu cài đặt curl -4. Hãy chạy: sudo apt-get install curl -4 (hoặc tương tự)"
  exit 1
fi

if ! command -v docker &> /dev/null; then
  echo "❌ Yêu cầu cài đặt Docker. Hãy chạy: sudo apt-get install docker.io (hoặc tương tự)"
  exit 1
fi

# if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
#   echo "❌ Yêu cầu cài đặt Docker Compose. Hãy chạy: sudo apt-get install docker-compose (hoặc cài Docker Compose Plugin)"
#   exit 1
# fi

# ---------- Load existing .env file if it exists ----------
if [ -f "$ENV_FILE" ]; then
  echo "🔍 Tìm thấy tệp $ENV_FILE, đang nạp biến môi trường..."
  source "$ENV_FILE"
fi

# ---------- User Input or Environment Variables ----------
clear
echo "========================================"
echo "🔧 AZTEC PROVER DEPLOYMENT WIZARD"
echo "========================================"

# WAN IP
WAN_IP=${WAN_IP:-}
if [ -z "$WAN_IP" ]; then
  echo "🔍 Đang lấy WAN IP tự động..."
  WAN_IP=$(curl -4 -s ifconfig.me)
  if ! validate_ip "$WAN_IP"; then
    echo "❌ Không thể lấy WAN IP tự động"
    read -p "👉 Vui lòng nhập WAN IP thủ công (e.g., 111.123.456.789): " WAN_IP
    validate_ip "$WAN_IP"
  fi
fi
echo "✅ WAN IP: $WAN_IP"

# Sepolia RPC URL
RPC_SEPOLIA=${RPC_SEPOLIA:-}
if [ -z "$RPC_SEPOLIA" ]; then
  read -p "👉 Enter Sepolia RPC URL: " RPC_SEPOLIA
fi
validate_url "$RPC_SEPOLIA"

# Beacon API URL
BEACON_SEPOLIA=${BEACON_SEPOLIA:-}
if [ -z "$BEACON_SEPOLIA" ]; then
  read -p "👉 Enter Beacon API URL: " BEACON_SEPOLIA
fi
validate_url "$BEACON_SEPOLIA"

# Publisher Private Key
PRIVATE_KEY=${PRIVATE_KEY:-}
if [ -z "$PRIVATE_KEY" ]; then
  read -p "👉 Enter Publisher Private Key: " PRIVATE_KEY
fi
[ -z "$PRIVATE_KEY" ] && { echo "❌ Private Key required"; exit 1; }

# Prover ID
PROVER_ID=${PROVER_ID:-}
if [ -z "$PROVER_ID" ]; then
  read -p "👉 Enter Prover ID: " PROVER_ID
fi
[ -z "$PROVER_ID" ] && { echo "❌ Prover ID required"; exit 1; }

# Number of Agents
AGENT_COUNT=${AGENT_COUNT:-}
if [ -z "$AGENT_COUNT" ]; then
  read -p "👉 Number of agents (≥1): " AGENT_COUNT
fi
validate_number "$AGENT_COUNT"

# ---------- Save to .env file ----------
cat > "$ENV_FILE" <<EOF
WAN_IP=$WAN_IP
RPC_SEPOLIA=$RPC_SEPOLIA
BEACON_SEPOLIA=$BEACON_SEPOLIA
PRIVATE_KEY=$PRIVATE_KEY
PROVER_ID=$PROVER_ID
AGENT_COUNT=$AGENT_COUNT
EOF
echo "📝 Đã lưu các giá trị vào $ENV_FILE"

# ---------- Create data directories ----------
mkdir -p "$DATA_DIR/node" "$DATA_DIR/broker"
echo "📁 Đã tạo thư mục dữ liệu: $DATA_DIR/node, $DATA_DIR/broker"

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