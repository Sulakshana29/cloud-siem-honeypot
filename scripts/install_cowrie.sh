#!/bin/bash
set -e

# ── 1. System deps ────────────────────────────────────────────────────────────
sudo apt-get update -y
sudo apt-get install -y git python3-venv python3-dev libssl-dev libffi-dev \
  build-essential libpython3-dev python3-minimal authbind virtualenv

# ── 2. Cowrie user (never run as root) ───────────────────────────────────────
id -u cowrie &>/dev/null || sudo adduser --disabled-password --gecos "" cowrie

# ── 3. Clone Cowrie ───────────────────────────────────────────────────────────
sudo su - cowrie -c "
  if [ ! -d '/home/cowrie/cowrie' ]; then
    git clone https://github.com/cowrie/cowrie.git /home/cowrie/cowrie
  fi
  cd /home/cowrie/cowrie
  python3 -m venv cowrie-env
  source cowrie-env/bin/activate
  pip install --upgrade pip
  pip install -r requirements.txt
"

# ── 4. Configure Cowrie ───────────────────────────────────────────────────────
sudo su - cowrie -c "
  cd /home/cowrie/cowrie
  cp src/cowrie/data/etc/cowrie.cfg.dist etc/cowrie.cfg
"

# Edit cowrie.cfg — key settings:
# cowrie.cfg.dist ships these lines commented out — uncomment and set them:
sudo sed -i \
  -e 's/^#hostname = svr04/hostname = webserver01/' \
  -e 's/^#listen_port = 2222/listen_port = 2222/' \
  /home/cowrie/cowrie/etc/cowrie.cfg

# NOTE: No iptables/authbind needed — Terraform already opens port 2222 to
# the internet via the security group. Real admin SSH stays on port 22,
# restricted to your IP only. Cowrie listens on 2222. No port forwarding required.

# ── 5. systemd service ───────────────────────────────────────────────────────
cat << 'EOF' | sudo tee /etc/systemd/system/cowrie.service
[Unit]
Description=Cowrie SSH/Telnet Honeypot
After=network.target

[Service]
Type=simple
User=cowrie
WorkingDirectory=/home/cowrie/cowrie
Environment=PYTHONPATH=/home/cowrie/cowrie/src
ExecStart=/home/cowrie/cowrie/cowrie-env/bin/twistd --umask 0022 --nodaemon --pidfile= -l - cowrie
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable cowrie
sudo systemctl start cowrie
sudo systemctl status cowrie
