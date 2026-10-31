#!/usr/bin/env bash
set -euo pipefail

export STARTMODE="0"

# Define color codes
RED='\033[31m'
GREEN='\033[32m'
NC='\033[0m' # No Color

# Get the EUI-ID
cd ./util_chip_id/
./chip_id > ./chip_id_output.txt
sed -n 's/.*concentrator EUI: 0x\([0-9a-fA-F]*\).*/\1/p' ./chip_id_output.txt > ./chip_id.txt

# Print the EUI Output
export GATEWAY_ID=$(cat ./chip_id.txt)
echo -e "${GREEN}EUI: ${GATEWAY_ID}${NC}"
cd ..

if [ "$DEBUG" -eq 1 ]; then
  echo "INFO: Debug mode is enabled. Please note the EUI-NUMBER."
  echo "exiting Container in 10 seconds"
  sleep 10
  exit 1
elif [ -e /opt/docker/lorawan-gateway/global_conf.json ]; then
  echo "INFO: global_conf.json file is found."
  STARTMODE="2"
elif [ -n "$GATEWAY_ID" ] && [ -n "$SERVER_ADDRESS" ] && [ -n "$SERVER_PORT_UP" ] && [ -n "$SERVER_PORT_DOWN" ]; then
  echo "INFO: GatewayID/ServerAddress/ServerPortUp/ServerPortDown is set."
  echo -e "INFO: "${GREEN}"GatewayID: "${GATEWAY_ID}${NC}
  echo -e "INFO: "${GREEN}"ServerAddress: "${SERVER_ADDRESS}${NC}
  echo -e "INFO: "${GREEN}"ServerPortUp: "${SERVER_PORT_UP}${NC}
  echo -e "INFO: "${GREEN}"ServerPortDown: "${SERVER_PORT_DOWN}${NC}
  STARTMODE="1"
else
  echo "ERROR: GatewayID/ServerAddress/ServerPortUp/ServerPortDown is not set."
  echo "ERROR: global_conf.json file is not found."
  echo "ERROR: Debug mode is not enabled."
  echo -e ${RED}"ERROR: Please check if the container is running with "--privileged" flag."${NC}
  echo "INFO: Exiting Container in 10 seconds"
  sleep 10
  exit 1
fi

# Copy the global_conf.json file to the test_conf file
cp ./packet_forwarder/global_conf.json.sx1250.EU868 ./packet_forwarder/test_conf

# Remove unwanted comments from the test_conf file
# The pattern matches the SHORTEST /* ... */ run. A greedy "/\*.*\*/" would eat
# everything between the first and last comment on a line, silently deleting
# real JSON when upstream puts two comments on one line.
sed 's|/\*[^*]*\(\*\+[^*/][^*]*\)*\*\+/||g' ./packet_forwarder/test_conf > ./packet_forwarder/test_conf.json

# Add the Gateway Configuration to the test_conf.json file
# .gateway_conf.gps_tty_path = "" -> is uesed to disable GPS functions because the GPS module does not work in the Docker container

if [ "$STARTMODE" -eq "1" ]; then
  jq --arg gatewayID "$GATEWAY_ID" \
     --arg serverAddress "$SERVER_ADDRESS" \
     --argjson serverPortUp $SERVER_PORT_UP \
     --argjson serverPortDown $SERVER_PORT_DOWN \
    '
    .gateway_conf.gateway_ID = $gatewayID |
    .gateway_conf.server_address = $serverAddress |
    .gateway_conf.serv_port_up = $serverPortUp |
    .gateway_conf.serv_port_down = $serverPortDown |
    .gateway_conf.gps_tty_path = "" |
    .gateway_conf.autoquit_threshold = 10 |
    .gateway_conf.servers = [
      {
        "gateway_ID": $gatewayID,
        "server_address": $serverAddress,
        "serv_port_up": $serverPortUp,
        "serv_port_down": $serverPortDown,
        "serv_enabled": true
      }
    ]
    ' ./packet_forwarder/test_conf.json > ./packet_forwarder/temp.json && \
    mv ./packet_forwarder/temp.json ./packet_forwarder/test_conf.json    
elif [ "$STARTMODE" -eq "2" ]; then
  # Check the fields we copy actually exist. Without this jq happily writes
  # nulls into test_conf.json and exits 0, and the forwarder starts up pointed
  # at no server at all - which looks like a running gateway but forwards
  # nothing.
  if ! jq -e '(.gateway_conf.gateway_ID? // empty) and (.gateway_conf.servers[0].server_address? // empty)' \
       /opt/docker/lorawan-gateway/global_conf.json > /dev/null 2>&1; then
    echo -e ${RED}"ERROR: global_conf.json is missing gateway_conf.gateway_ID or gateway_conf.servers[0].server_address."${NC}
    echo "INFO: Re-download the file from the TTN console gateway page."
    echo "INFO: Exiting Container in 10 seconds"
    sleep 10
    exit 1
  fi
  jq --slurpfile src /opt/docker/lorawan-gateway/global_conf.json '
    .gateway_conf.gateway_ID = $src[0].gateway_conf.gateway_ID |
    .gateway_conf.server_address = $src[0].gateway_conf.servers[0].server_address |
    .gateway_conf.serv_port_up = $src[0].gateway_conf.servers[0].serv_port_up |
    .gateway_conf.serv_port_down = $src[0].gateway_conf.servers[0].serv_port_down |
    .gateway_conf.gps_tty_path = "" |
    .gateway_conf.autoquit_threshold = 10 |
    .gateway_conf.servers = $src[0].gateway_conf.servers
  ' ./packet_forwarder/test_conf.json > ./packet_forwarder/temp.json && \
  mv ./packet_forwarder/temp.json ./packet_forwarder/test_conf.json
fi

# Run the Lora Packet Forwarder
cd ./packet_forwarder/

# exec replaces the shell so lora_pkt_fwd becomes PID 1 and receives the SIGTERM
# sent by "docker stop", which lets it shut the concentrator down cleanly.
exec ./lora_pkt_fwd -c ./test_conf.json
