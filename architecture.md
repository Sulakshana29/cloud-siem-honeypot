# Architecture — Cloud SIEM Honeypot

## Overview

This project implements a cloud-native Security Operations Center (SOC) pipeline on AWS.
A live SSH honeypot captures real attacker activity, and the data is automatically centralized,
normalized, and (in later phases) visualized in a SIEM dashboard.

---

## Data Flow

```mermaid
flowchart TD
    A["🌐 Internet\n(Attacker)"]:::attacker

    subgraph AWS_VPC ["AWS VPC  (10.10.0.0/16) — Isolated Network"]
        direction TB

        SG["🛡️ Security Group\n— Port 22: Admin only (your IP)\n— Port 2222: Open to internet\n— Port 23: Open to internet"]:::sg

        subgraph EC2 ["EC2 Instance  t3.micro · Ubuntu 22.04"]
            COWRIE["🍯 Cowrie Honeypot\nListens on :2222\nAccepts any credentials\nLogs all commands"]:::cowrie
            LOGS["📄 cowrie.json\n/home/cowrie/cowrie/var/log/cowrie/"]:::log
            CWA["📡 CloudWatch Agent\n(continuously tails cowrie.json)"]:::agent
        end
    end

    subgraph AWS_CLOUD ["AWS Cloud Services"]
        CWL["📊 CloudWatch Log Group\n/honeypot/cowrie"]:::cloudwatch
        S3["🪣 S3 Data Lake\nnormalized-honeypot-logs/"]:::s3
        LAMBDA["⚡ Lambda Function\nnormalize_logs.py"]:::lambda
        ATHENA["🔍 Athena\nThreat Hunting SQL"]:::athena
        ELK["📈 ELK Stack\nKibana Dashboards"]:::elk
    end

    ADMIN["👤 You (Admin)\nSSH on Port 22"]:::admin

    A -->|"SSH brute-force\n:2222"| SG
    ADMIN -->|"Admin SSH\n:22"| SG
    SG --> COWRIE
    COWRIE -->|"Writes JSON events"| LOGS
    LOGS -->|"Streams in real time"| CWA
    CWA -->|"CloudWatch PutLogEvents API"| CWL

    CWL -->|"Triggers on new events"| LAMBDA
    LAMBDA -->|"Cleaned structured JSON"| S3
    S3 -->|"SQL queries"| ATHENA
    S3 -->|"Log ingestion"| ELK

    classDef attacker fill:#c0392b,color:#fff,stroke:#922b21
    classDef sg fill:#e67e22,color:#fff,stroke:#ca6f1e
    classDef cowrie fill:#8e44ad,color:#fff,stroke:#6c3483
    classDef log fill:#2c3e50,color:#ecf0f1,stroke:#1a252f
    classDef agent fill:#16a085,color:#fff,stroke:#0e6655
    classDef cloudwatch fill:#2980b9,color:#fff,stroke:#1a5276
    classDef s3 fill:#27ae60,color:#fff,stroke:#1e8449
    classDef lambda fill:#f39c12,color:#fff,stroke:#b7770d
    classDef athena fill:#1abc9c,color:#fff,stroke:#148f77
    classDef elk fill:#2471a3,color:#fff,stroke:#1a5276
    classDef admin fill:#555,color:#fff,stroke:#333
```

---

## Phase Status

| Phase | What | Status |
|---|---|---|
| **Phase 1** | Terraform VPC + EC2 + Security Groups | ✅ Complete |
| **Phase 1** | Cowrie Honeypot installed & running as systemd service | ✅ Complete |
| **Phase 2** | IAM Role (least privilege) attached to EC2 | ✅ Complete |
| **Phase 2** | CloudWatch Agent streaming `cowrie.json` to `/honeypot/cowrie` | ✅ Complete |
| **Phase 3** | Lambda function to auto-normalize logs → S3 Data Lake | 🔄 In Progress |
| **Phase 4** | Athena threat hunting queries | ⏳ Planned |
| **Phase 5** | ELK Stack SIEM with Kibana dashboards | ⏳ Planned |
| **Phase 6** | SOAR — Lambda "Bouncer" auto-banning attacker IPs | ⏳ Planned |

---

## Security Design Principles

| Principle | Implementation |
|---|---|
| **Isolation** | Dedicated VPC with no peering to any production account |
| **Least Privilege** | IAM Role grants CloudWatch write-only, nothing else |
| **Admin Lockdown** | Port 22 restricted to operator IP via Security Group |
| **Tamper-Resistant Logs** | CloudWatch streams data off-server before attacker can delete it |
| **Non-root Honeypot** | Cowrie runs as the `cowrie` system user, never as root |
| **Zero Real Secrets** | All credentials inside Cowrie are synthetic/fake |
