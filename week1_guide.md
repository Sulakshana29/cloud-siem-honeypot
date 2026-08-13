# Week 1 — Cloud SIEM Honeypot Lab: How-To Guide

## Overview

This guide walks you through each day of Week 1 step-by-step. The goal is to stand up a **Cowrie SSH honeypot** on AWS EC2, capture attacker activity, and normalize raw logs into structured JSON for later ingestion into a SIEM.

---

## Aug 10 — Repository Setup & Threat Model

### Part A: GitHub Repository Structure

Create the following folder/file layout locally and push to GitHub.

```
cloud-siem-honeypot-lab/
├── README.md
├── architecture.md
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── scripts/
│   └── install_cowrie.sh
├── docs/
│   └── threat-model.md
└── screenshots/
    └── .gitkeep
```

**Commands:**
```bash
# In d:\Projects\cloud-siem-honeypot
git init
mkdir terraform scripts docs screenshots
New-Item README.md, architecture.md -ItemType File
New-Item scripts\install_cowrie.sh, docs\threat-model.md -ItemType File
New-Item screenshots\.gitkeep -ItemType File
git add .
git commit -m "chore: initial repo scaffold"
git remote add origin https://github.com/YOUR_USERNAME/cloud-siem-honeypot-lab.git
git push -u origin main
```

### Part B: Threat Model (docs/threat-model.md)

Write answers to these questions:

| Question | Answer for this lab |
|---|---|
| **What assets exist?** | EC2 instance, its IP, Cowrie logs |
| **What are we protecting?** | Nothing real — this is a sacrificial host |
| **Who are the threat actors?** | Automated scanners, script kiddies, bot nets |
| **What data is allowed on this host?** | Only synthetic/fake credentials in Cowrie config |
| **What is NOT allowed?** | Real AWS creds, personal data, prod secrets |
| **Blast radius if compromised?** | Zero — dedicated VPC, no peering, no prod access |

> [!CAUTION]
> **Golden rule**: The EC2 instance must have **zero access** to your AWS account beyond its own VPC. Use a dedicated IAM role with no permissions, or no role at all.

---

## Aug 11 — Terraform: VPC, Subnet, SG, EC2

### How Terraform works (quick primer)

Terraform is Infrastructure-as-Code. You write `.tf` files describing the AWS resources you want, run `terraform plan` to preview, and `terraform apply` to create them.

### File: `terraform/variables.tf`

```hcl
variable "aws_region" {
  default = "us-east-1"
}

variable "your_ip" {
  description = "Your home/office IP for SSH admin access (CIDR notation, e.g. 1.2.3.4/32)"
  type        = string
}

variable "key_name" {
  description = "Name of an existing EC2 key pair"
  type        = string
}

variable "ami_id" {
  # Ubuntu 22.04 LTS in us-east-1 — check AWS console for your region
  default = "ami-0c7217cdde317cfec"
}
```

### File: `terraform/main.tf`

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── Networking ───────────────────────────────────────────────────────────────

resource "aws_vpc" "honeypot" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "honeypot-vpc" }
}

resource "aws_internet_gateway" "honeypot" {
  vpc_id = aws_vpc.honeypot.id
  tags   = { Name = "honeypot-igw" }
}

resource "aws_subnet" "honeypot_public" {
  vpc_id                  = aws_vpc.honeypot.id
  cidr_block              = "10.10.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags                    = { Name = "honeypot-public-subnet" }
}

resource "aws_route_table" "honeypot" {
  vpc_id = aws_vpc.honeypot.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.honeypot.id
  }
  tags = { Name = "honeypot-rt" }
}

resource "aws_route_table_association" "honeypot" {
  subnet_id      = aws_subnet.honeypot_public.id
  route_table_id = aws_route_table.honeypot.id
}

# ─── Security Group ──────────────────────────────────────────────────────────

resource "aws_security_group" "honeypot" {
  name   = "honeypot-sg"
  vpc_id = aws_vpc.honeypot.id

  # Admin SSH — only from YOUR IP
  ingress {
    description = "Admin SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  # Cowrie listens on 2222 — open to internet to attract attackers
  ingress {
    description = "Honeypot SSH (Cowrie)"
    from_port   = 2222
    to_port     = 2222
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Cowrie Telnet honeypot (optional)
  ingress {
    description = "Honeypot Telnet (Cowrie)"
    from_port   = 23
    to_port     = 23
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "honeypot-sg" }
}

# ─── EC2 Instance ─────────────────────────────────────────────────────────────

resource "aws_instance" "honeypot" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.honeypot_public.id
  vpc_security_group_ids = [aws_security_group.honeypot.id]
  key_name               = var.key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "cowrie-honeypot" }
}
```

### File: `terraform/outputs.tf`

```hcl
output "honeypot_public_ip" {
  value = aws_instance.honeypot.public_ip
}
```

### File: `terraform/terraform.tfvars.example`

```hcl
aws_region = "us-east-1"
your_ip    = "YOUR.IP.HERE/32"   # Replace with your real IP
key_name   = "my-keypair-name"
```

> [!WARNING]
> Copy this to `terraform.tfvars` and fill in real values. **Never commit `terraform.tfvars` to Git** — add it to `.gitignore`.

---

## Aug 12 — Provision EC2 & Verify SSH

### Prerequisites

1. Install [AWS CLI](https://aws.amazon.com/cli/) and run `aws configure`
2. Install [Terraform](https://developer.hashicorp.com/terraform/install)
3. Create an EC2 Key Pair in the AWS Console → EC2 → Key Pairs → Download `.pem`

### Steps

```powershell
cd d:\Projects\cloud-siem-honeypot\terraform

# Initialize Terraform (downloads AWS provider)
terraform init

# Preview what will be created
terraform plan -var-file="terraform.tfvars"

# Create the infrastructure
terraform apply -var-file="terraform.tfvars"
# Type "yes" when prompted

# Note the output IP address
terraform output honeypot_public_ip
```

### Verify SSH

```powershell
# Fix key permissions (on Linux/Mac use chmod 400)
# On Windows, use the key directly with ssh:
ssh -i "C:\path\to\your-key.pem" ubuntu@<PUBLIC_IP>

# If connected — you should see Ubuntu welcome message
# Type 'exit' to disconnect
```

---

## Aug 13 — Install Cowrie & Configure Logging

### What is Cowrie?

Cowrie is a medium-to-high interaction SSH/Telnet honeypot. It:
- Accepts any username/password (logs them)
- Provides a fake shell environment
- Records all commands attackers run
- Logs everything to JSON files

### Installation Script (`scripts/install_cowrie.sh`)

Copy and run this on the EC2 instance:

```bash
#!/bin/bash
set -e

# ── 1. System deps ────────────────────────────────────────────────────────────
sudo apt-get update -y
sudo apt-get install -y git python3-venv python3-dev libssl-dev libffi-dev \
  build-essential libpython3-dev python3-minimal authbind virtualenv

# ── 2. Cowrie user (never run as root) ───────────────────────────────────────
sudo adduser --disabled-password --gecos "" cowrie

# ── 3. Clone Cowrie ───────────────────────────────────────────────────────────
sudo su - cowrie -c "
  git clone https://github.com/cowrie/cowrie.git /home/cowrie/cowrie
  cd /home/cowrie/cowrie
  python3 -m venv cowrie-env
  source cowrie-env/bin/activate
  pip install --upgrade pip
  pip install -r requirements.txt
"

# ── 4. Configure Cowrie ───────────────────────────────────────────────────────
sudo su - cowrie -c "
  cd /home/cowrie/cowrie
  cp etc/cowrie.cfg.dist etc/cowrie.cfg
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
ExecStart=/home/cowrie/cowrie/cowrie-env/bin/python bin/cowrie start -n
ExecStop=/home/cowrie/cowrie/cowrie-env/bin/python bin/cowrie stop
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable cowrie
sudo systemctl start cowrie
sudo systemctl status cowrie
```

### Run the script on EC2

```powershell
# Copy script to EC2
scp -i "your-key.pem" scripts/install_cowrie.sh ubuntu@<PUBLIC_IP>:~

# SSH in and run it
ssh -i "your-key.pem" ubuntu@<PUBLIC_IP>
chmod +x install_cowrie.sh
sudo bash install_cowrie.sh
```

### Verify it starts after reboot

```bash
# On EC2
sudo reboot

# SSH back in after ~60s
ssh -i "your-key.pem" ubuntu@<PUBLIC_IP>
sudo systemctl status cowrie   # should show "active (running)"
```

---

## Aug 14 — Generate Safe Test Activity

### Goal

Send fake attack traffic FROM YOUR OWN MACHINE to the honeypot's port 2222. This proves Cowrie is recording activity before real internet traffic arrives.

### Method 1: Manual SSH login attempts

```powershell
# From your local machine — try wrong passwords, watch them get logged
ssh -p 2222 -o StrictHostKeyChecking=no root@<PUBLIC_IP>
# Enter any password — it will "accept" after Cowrie's configured delay
# Type some fake commands: ls, whoami, cat /etc/passwd
# Type exit
```

### Method 2: Script multiple attempts (`scripts/test_activity.sh`)

```bash
#!/bin/bash
# Run from your local Linux/Mac or WSL on Windows
TARGET_IP="YOUR_HONEYPOT_IP"
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
```

> [!NOTE]
> Install `sshpass` on WSL: `sudo apt install sshpass`

---

## Aug 15 — Inspect Raw Logs

### Where Cowrie logs live

```
/home/cowrie/cowrie/var/log/cowrie/
├── cowrie.log          ← Human-readable text log
└── cowrie.json         ← Structured JSON log (the important one)
```

### View live logs (on EC2)

```bash
# Follow live events
sudo tail -f /home/cowrie/cowrie/var/log/cowrie/cowrie.log

# View raw JSON events
cat /home/cowrie/cowrie/var/log/cowrie/cowrie.json | python3 -m json.tool | head -100
```

### Key fields to identify in each JSON event

| Field | Description | Example |
|---|---|---|
| `timestamp` | ISO 8601 event time | `"2025-08-15T12:34:56.789Z"` |
| `src_ip` | Attacker source IP | `"185.234.x.x"` |
| `username` | Login username tried | `"root"` |
| `password` | Password attempted | `"123456"` |
| `eventid` | Event type code | `"cowrie.login.failed"` |
| `session` | Unique session UUID | `"abc123..."` |
| `input` | Command typed in shell | `"cat /etc/shadow"` |
| `message` | Human-readable description | `"login attempt [root/123456] failed"` |

### Common Cowrie event types

| eventid | What it means |
|---|---|
| `cowrie.session.connect` | New connection established |
| `cowrie.login.failed` | Auth attempt — wrong password |
| `cowrie.login.success` | Auth attempt — accepted (all accepted) |
| `cowrie.command.input` | Command typed by attacker |
| `cowrie.session.file_download` | Attacker tried to download a file |
| `cowrie.session.closed` | Connection ended |

---

## Aug 16 — Log Parser / Normalization Script

### Goal

Write a Python script that reads `cowrie.json`, filters the important events, and outputs clean normalized JSON suitable for SIEM ingestion.

### File: `scripts/normalize_logs.py`

```python
#!/usr/bin/env python3
"""
Cowrie Log Normalizer
Reads raw Cowrie JSON logs and outputs normalized events for SIEM ingestion.
"""

import json
import sys
import argparse
from datetime import datetime, timezone
from pathlib import Path


# Events we care about — filter out noise
RELEVANT_EVENTS = {
    "cowrie.session.connect",
    "cowrie.login.failed",
    "cowrie.login.success",
    "cowrie.command.input",
    "cowrie.session.file_download",
    "cowrie.session.closed",
}


def normalize_event(raw: dict) -> dict | None:
    """
    Convert a raw Cowrie JSON event into a normalized SIEM-ready record.
    Returns None if the event should be skipped.
    """
    event_id = raw.get("eventid", "")

    if event_id not in RELEVANT_EVENTS:
        return None

    # Parse and re-emit timestamp in UTC ISO 8601
    raw_ts = raw.get("timestamp", "")
    try:
        ts = datetime.fromisoformat(raw_ts.replace("Z", "+00:00"))
        normalized_ts = ts.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    except (ValueError, AttributeError):
        normalized_ts = raw_ts  # keep original if parse fails

    normalized = {
        "timestamp":    normalized_ts,
        "source":       "cowrie-honeypot",
        "event_type":   event_id,
        "session_id":   raw.get("session", ""),
        "src_ip":       raw.get("src_ip", ""),
        "src_port":     raw.get("src_port", 0),
        "dst_port":     raw.get("dst_port", 0),
        "username":     raw.get("username", ""),
        "password":     raw.get("password", ""),
        "command":      raw.get("input", ""),
        "message":      raw.get("message", ""),
        "sensor":       raw.get("sensor", ""),
    }

    # Add download-specific fields
    if event_id == "cowrie.session.file_download":
        normalized["file_url"]  = raw.get("url", "")
        normalized["file_sha"]  = raw.get("shasum", "")
        normalized["file_size"] = raw.get("outfile", "")

    return normalized


def parse_log_file(input_path: Path) -> list[dict]:
    """Parse a Cowrie JSON log file (one JSON object per line)."""
    results = []

    with open(input_path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                raw = json.loads(line)
                normalized = normalize_event(raw)
                if normalized:
                    results.append(normalized)
            except json.JSONDecodeError as e:
                print(f"[WARN] Line {line_num}: JSON parse error — {e}", file=sys.stderr)

    return results


def main():
    parser = argparse.ArgumentParser(
        description="Normalize Cowrie honeypot logs to structured JSON"
    )
    parser.add_argument(
        "input",
        type=Path,
        help="Path to cowrie.json log file"
    )
    parser.add_argument(
        "-o", "--output",
        type=Path,
        default=None,
        help="Output file (default: stdout)"
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Print summary statistics after parsing"
    )
    args = parser.parse_args()

    if not args.input.exists():
        print(f"[ERROR] Input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    events = parse_log_file(args.input)

    # Output
    output_json = json.dumps(events, indent=2)

    if args.output:
        args.output.write_text(output_json, encoding="utf-8")
        print(f"[OK] Wrote {len(events)} events to {args.output}")
    else:
        print(output_json)

    # Optional stats
    if args.stats:
        from collections import Counter
        event_counts = Counter(e["event_type"] for e in events)
        ip_counts = Counter(e["src_ip"] for e in events if e["src_ip"])
        print("\n── Event type summary ──", file=sys.stderr)
        for ev, count in event_counts.most_common():
            print(f"  {ev:<40} {count}", file=sys.stderr)
        print("\n── Top 10 source IPs ──", file=sys.stderr)
        for ip, count in ip_counts.most_common(10):
            print(f"  {ip:<20} {count}", file=sys.stderr)


if __name__ == "__main__":
    main()
```

### How to run the parser

```bash
# On EC2, after copying the script up:
scp -i "your-key.pem" scripts/normalize_logs.py ubuntu@<PUBLIC_IP>:~

# SSH in and run:
python3 normalize_logs.py /home/cowrie/cowrie/var/log/cowrie/cowrie.json \
  --output normalized_events.json \
  --stats

# View a sample of the output
head -50 normalized_events.json
```

### Example normalized output

```json
[
  {
    "timestamp": "2025-08-16T08:23:11.402Z",
    "source": "cowrie-honeypot",
    "event_type": "cowrie.login.failed",
    "session_id": "a3f1b2c4d5e6",
    "src_ip": "185.234.100.12",
    "src_port": 54321,
    "dst_port": 2222,
    "username": "root",
    "password": "123456",
    "command": "",
    "message": "login attempt [root/123456] failed",
    "sensor": ""
  }
]
```

---

## Quick Reference: Tools & Their Roles

| Tool | Role in this lab |
|---|---|
| **Terraform** | Provision AWS infrastructure (VPC, EC2, SG) as code |
| **Cowrie** | SSH honeypot — records attacker behavior |
| **Python parser** | Normalize raw logs → structured JSON for SIEM |
| **GitHub** | Version control for all lab artifacts |
| **AWS EC2** | The sacrificial server exposed to the internet |

---

## Security Checklist Before Going Live

- [ ] `terraform.tfvars` is in `.gitignore`
- [ ] No real AWS credentials on the EC2 instance
- [ ] Admin SSH (port 22) restricted to your IP only
- [ ] Cowrie running as a non-root `cowrie` user
- [ ] No VPC peering to any production account
- [ ] All secrets in `cowrie.cfg` are fake/synthetic
