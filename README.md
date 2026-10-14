# 🍯 Cloud SIEM Honeypot

![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform)
![AWS](https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazonaws)
![Python](https://img.shields.io/badge/Language-Python_3.10-3776AB?logo=python)
![Wazuh](https://img.shields.io/badge/SIEM-Wazuh-3595F7)
![MITRE ATT&CK](https://img.shields.io/badge/Mapped_to-MITRE_ATT%26CK-E3242B)
![License](https://img.shields.io/badge/License-MIT-green)

A **fully automated, production-style cloud threat intelligence pipeline** built on AWS.

A live Cowrie SSH honeypot captures real attacker activity from the public internet. Every login attempt, command run, and malware download is automatically streamed to CloudWatch, then flows down two paths:

- **Hunt:** a serverless Lambda normalizes events into a partitioned S3 data lake that you can query with SQL through Athena.
- **Detect:** a Wazuh SIEM pulls the same stream, runs custom detection rules mapped to **MITRE ATT&CK**, and raises alerts on brute force, successful intrusions, persistence attempts, cryptominers and malware downloads.

All AWS infrastructure is provisioned with Terraform, with no manual console clicks.

### ✨ Highlights
- Real attacker telemetry, not simulated data
- Least-privilege IAM for every component (EC2, Lambda, Athena analyst, Wazuh reader)
- 12 custom Wazuh rules, including time-window brute-force correlation
- Hive-partitioned data lake with 12 ready-made threat hunting queries

---

## 🏗️ Architecture

```
Internet (Attackers)
        │
        │  SSH brute-force on :2222 / Telnet on :23
        ▼
┌─────────────────────────────────────────┐
│  AWS VPC  10.10.0.0/16  (Isolated)      │
│  ┌──────────────────────────────────┐   │
│  │  EC2 t3.micro · Ubuntu 22.04     │   │
│  │  ┌────────────────────────────┐  │   │
│  │  │  Cowrie Honeypot (:2222)   │  │   │
│  │  │  Accepts any credentials   │  │   │
│  │  │  Logs all commands         │  │   │
│  │  └──────────┬─────────────────┘  │   │
│  │             │ cowrie.json         │   │
│  │  ┌──────────▼─────────────────┐  │   │
│  │  │  CloudWatch Agent          │  │   │
│  │  │  (tails log file live)     │  │   │
│  │  └──────────┬─────────────────┘  │   │
│  └─────────────┼────────────────────┘   │
└───────────────-┼────────────────────────┘
                 │ PutLogEvents
                 ▼
        CloudWatch Logs  /honeypot/cowrie
                 │
       ┌─────────┴──────────────────────────┐
       │ Subscription Filter (push)         │ AWS module pull (every 5 min)
       ▼                                    │ read-only IAM user
Lambda: CowrieLogNormalizer                 ▼
(decode gzip → normalize → partition)   ┌──────────────────────────────┐
       │                                │  Wazuh SIEM (Docker)         │
       ▼                                │  JSON decoder → custom rules │
S3 Data Lake: logs/year=/month=/day=/   │  → MITRE ATT&CK alerts       │
       │                                │  Indexer + Dashboard         │
       ▼                                └──────────────┬───────────────┘
Athena + Glue                                          │ (Phase 6)
Threat Hunting (SQL)                                   ▼
                                            SOAR: auto-block attacker IPs
```

---

## 🛠️ Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| Infrastructure | **Terraform** | Entire AWS stack as code — reproducible in minutes |
| Compute | **AWS EC2 t3.micro** | Hosts the honeypot, Ubuntu 22.04 |
| Honeypot | **Cowrie** | Medium-high interaction SSH/Telnet honeypot |
| Log Streaming | **AWS CloudWatch Agent** | Tails cowrie.json → ships to CloudWatch in real time |
| Processing | **AWS Lambda (Python 3.10)** | Serverless normalizer triggered by CloudWatch |
| Storage | **AWS S3** | Encrypted, partitioned data lake |
| Query Layer | **AWS Athena + Glue** | Serverless SQL threat hunting on the data lake |
| SIEM | **Wazuh 4.x (Docker)** | Real-time detection rules, ATT&CK mapping, alert dashboards |
| IAM | **AWS IAM** | Least-privilege roles for every service |

---

## 📸 Screenshots

![CloudWatch log stream](screenshots/Screenshot%202026-09-17%20162716.png)

![CloudWatch Agent](screenshots/Screenshot%202026-09-17%20162750.png)

### 🪣 S3 Data Lake — Hive-Partitioned Normalized Events
![S3 data lake](screenshots/s3%20data.png)

### 🔍 Athena — Threat Hunting Query
![Athena query](screenshots/Athena_query.png)

### 📊 Athena — Real Attacker Data Results
![Athena query results](screenshots/Query_results.png)

### 🏗️ Terraform — Full Infrastructure as Code
![Terraform state list](screenshots/terraform%20state%20list.png)

### 🛡️ IAM — Least Privilege (CloudWatch Write-Only)
![IAM CloudWatch Agent Policy](screenshots/CloudWatchAgentPolicy.png)

---

## 📋 Phase Status

| Phase | What | Status |
|---|---|---|
| **Phase 1** | Terraform VPC + EC2 + Security Groups | ✅ Complete |
| **Phase 1** | Cowrie Honeypot installed as systemd service | ✅ Complete |
| **Phase 2** | IAM Role (least privilege) + CloudWatch Agent | ✅ Complete |
| **Phase 3** | Lambda log normalizer → S3 Data Lake | ✅ Complete |
| **Phase 4** | Glue Catalog + Athena workgroup + threat hunting SQL | ✅ Complete |
| **Phase 5** | Wazuh SIEM: CloudWatch ingestion + custom ATT&CK-mapped detection rules ([guide](docs/phase5_wazuh_guide.md)) | 🚧 In progress |
| **Phase 6** | SOAR: Wazuh alert → Lambda adds attacker IP to a WAF / NACL blocklist | ⏳ Planned |
| **Phase 7** | Threat intel enrichment: AbuseIPDB / GreyNoise for IPs, VirusTotal for malware hashes | ⏳ Planned |
| **Phase 8** | Hardening & CI: egress lockdown, `tfsec` + `terraform validate` in GitHub Actions, Lambda unit tests | ⏳ Planned |

---

## 🚨 Detection Rules (Wazuh)

Rules live in [`wazuh/cowrie_rules.xml`](wazuh/cowrie_rules.xml).

| Rule ID | Level | Detects | MITRE ATT&CK |
|---|---|---|---|
| 100102 | 5 | Failed login | T1110 Brute Force |
| 100103 | 10 | 10+ failed logins from one IP in 2 min | T1110.001 Password Guessing |
| 100104 | 10 | Successful login | T1078 Valid Accounts |
| 100110 | 6 | Shell command executed | T1059.004 Unix Shell |
| 100111 | 7 | System discovery (`uname`, `nproc`, ...) | T1082 System Information Discovery |
| 100112 | 12 | SSH key implant (`authorized_keys`) | T1098.004 SSH Authorized Keys |
| 100113 | 12 | Cron persistence | T1053.003 Cron |
| 100114 | 12 | Cryptominer deployment | T1496 Resource Hijacking |
| 100115 | 10 | `wget` / `curl` / `tftp` download command | T1105 Ingress Tool Transfer |
| 100120 | 13 | Malware file downloaded | T1105 Ingress Tool Transfer |

---

## 🔐 Security Design

| Principle | Implementation |
|---|---|
| **Network Isolation** | Dedicated VPC with no peering to any production environment |
| **Least Privilege IAM** | EC2 role → CloudWatch write only. Lambda role → S3 PutObject only |
| **Admin Lockdown** | Port 22 restricted to operator IP via Security Group |
| **Tamper-Resistant Logs** | CloudWatch streams data off-box before attacker can delete it |
| **Non-root Honeypot** | Cowrie runs as the `cowrie` system user, never as root |
| **Zero Real Secrets** | All credentials inside Cowrie are synthetic/fake |
| **Encrypted Storage** | S3 data lake uses AES-256 server-side encryption |

---

## 📡 What the Honeypot Captures

Every event is normalized to this schema and stored in S3:

```json
{
  "timestamp":  "2024-01-15T14:23:01.000Z",
  "source":     "cowrie-honeypot",
  "event_type": "cowrie.login.failed",
  "session_id": "abc123def456",
  "src_ip":     "198.51.100.42",
  "src_port":   54321,
  "dst_port":   2222,
  "username":   "root",
  "password":   "admin123"
}
```

**Captured event types:**

| Event | What it tells you |
|---|---|
| `cowrie.session.connect` | Who connected, from where |
| `cowrie.login.failed` | Credential spray attempts (username + password tried) |
| `cowrie.login.success` | Attacker got through auth — high-value session |
| `cowrie.command.input` | Post-login recon & attack commands |
| `cowrie.session.file_download` | Malware download URL + SHA256 hash |
| `cowrie.session.closed` | Session end — calculate duration |

---

## 🔍 Sample Threat Hunting Queries

```sql
-- Top attacking IPs
SELECT src_ip, COUNT(*) AS attempts
FROM cloud_siem_db.cowrie_logs
WHERE event_type = 'cowrie.login.failed'
GROUP BY src_ip ORDER BY attempts DESC LIMIT 10;

-- Most tried credentials
SELECT username, password, COUNT(*) AS tries
FROM cloud_siem_db.cowrie_logs
WHERE event_type = 'cowrie.login.failed'
GROUP BY username, password ORDER BY tries DESC LIMIT 20;

-- Commands run after successful login
SELECT timestamp, src_ip, command
FROM cloud_siem_db.cowrie_logs
WHERE event_type = 'cowrie.command.input'
ORDER BY timestamp DESC;
```

Full query set: [`docs/athena_queries.sql`](docs/athena_queries.sql)

---

## 🚀 Setup & Deployment

### Prerequisites
- AWS account with programmatic access configured (`aws configure`)
- Terraform >= 1.0
- An EC2 key pair created in your target region

### 1. Clone and configure
```bash
git clone https://github.com/YOUR_USERNAME/cloud-siem-honeypot.git
cd cloud-siem-honeypot/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
aws_region = "us-east-1"
your_ip    = "YOUR.PUBLIC.IP.HERE/32"   # find at whatismyip.com
key_name   = "your-ec2-keypair-name"
```

### 2. Deploy infrastructure
```bash
terraform init
terraform plan    # review what will be created
terraform apply   # deploy (~2 min)
```

### 3. Install Cowrie on the EC2
```bash
# Get the public IP from Terraform output
terraform output honeypot_public_ip

# SSH in
ssh -i your-key.pem ubuntu@<PUBLIC_IP>

# Run the install script
curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/cloud-siem-honeypot/main/scripts/install_cowrie.sh | bash
```

### 4. Verify the pipeline
```bash
# On EC2 — check Cowrie is running
sudo systemctl status cowrie

# Watch live attacker events (bots find you within minutes)
sudo journalctl -u cowrie -f
```

In AWS Console:
- **CloudWatch** → Log Groups → `/honeypot/cowrie` → should have live log streams
- **S3** → `cloud-siem-datalake-*` → check for files under `logs/`
- **Athena** → select workgroup `cloud-siem-workgroup`, database `cloud_siem_db` → run queries

### 5. (Optional) Connect the Wazuh SIEM
Follow [`docs/phase5_wazuh_guide.md`](docs/phase5_wazuh_guide.md). The short version:
```bash
terraform output wazuh_access_key_id
terraform output -raw wazuh_secret_access_key
# run wazuh-docker single-node, mount the credentials, add wazuh/aws_cloudwatch_wodle.xml
# to the manager config, then copy in wazuh/cowrie_rules.xml
```

### 6. Tear down (avoid AWS charges)
```bash
terraform destroy
```

---

## 💰 Estimated AWS Cost

| Resource | Cost |
|---|---|
| EC2 t3.micro | ~$0.0104/hr ≈ **$7.50/month** |
| S3 storage | Negligible for log volumes |
| Lambda invocations | Within free tier |
| CloudWatch ingestion | Within free tier for small log volumes |
| Athena queries | $5 per TB scanned (honeypot logs = pennies) |
| Wazuh polling CloudWatch | GetLogEvents API calls: pennies |
| Wazuh itself | **$0**: runs locally in Docker (on AWS it would need a t3.large, ~$60/month) |
| **Total** | **~$8–10/month** |

---

## 📁 Project Structure

```
cloud-siem-honeypot/
├── terraform/
│   ├── main.tf          # VPC, EC2, Security Groups, IAM, CloudWatch
│   ├── phase3.tf        # S3 Data Lake, Lambda normalizer
│   ├── phase4.tf        # Glue Catalog, Athena workgroup, IAM analyst policy
│   ├── phase5.tf        # Read-only IAM user for Wazuh CloudWatch ingestion
│   ├── variables.tf     # Input variables
│   └── outputs.tf       # EC2 public IP, bucket name
├── scripts/
│   ├── install_cowrie.sh    # Full Cowrie install + systemd setup
│   ├── setup_cloudwatch.sh  # CloudWatch Agent configuration
│   ├── lambda_function.py   # Serverless log normalizer (deployed to Lambda)
│   └── normalize_logs.py    # Local CLI normalizer for testing
├── wazuh/
│   ├── cowrie_rules.xml         # Custom detection rules (MITRE ATT&CK mapped)
│   ├── aws_cloudwatch_wodle.xml # Wazuh AWS module config for CloudWatch pull
│   └── docker-compose.manager-only.yml # Low-RAM (~0.6 GB) Wazuh for learning rules
└── docs/
    ├── architecture.md      # Detailed architecture with Mermaid diagram
    ├── threat-model.md      # STRIDE threat model
    ├── athena_queries.sql   # 12 ready-to-run threat hunting queries
    └── phase5_wazuh_guide.md # Step-by-step Wazuh SIEM integration guide
```
