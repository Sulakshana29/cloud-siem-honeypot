#!/bin/bash
set -e

echo "[*] Downloading Amazon CloudWatch Agent..."
wget https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/amazon-cloudwatch-agent.deb

echo "[*] Installing CloudWatch Agent..."
sudo dpkg -i -E /tmp/amazon-cloudwatch-agent.deb

echo "[*] Creating CloudWatch Agent configuration..."
cat << 'EOF' | sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "agent": {
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/home/cowrie/cowrie/var/log/cowrie/cowrie.json",
            "log_group_name": "/honeypot/cowrie",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
EOF

echo "[*] Starting CloudWatch Agent..."
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo "[*] CloudWatch Agent setup complete!"
