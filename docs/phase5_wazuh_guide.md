# Phase 5 — Wazuh SIEM: How-To Guide

## Overview

Up to Phase 4 you can **hunt**: you ask Athena a question and get an answer. A SIEM adds **detection**: it watches every event as it arrives, matches it against rules, and raises an alert without you asking. Each alert is mapped to a MITRE ATT&CK technique.

By the end of this phase you will have:

- Wazuh running in Docker on your laptop
- Wazuh pulling Cowrie logs straight from CloudWatch, with nothing changed on the honeypot
- Custom detection rules for brute force, successful logins, persistence, miners and malware downloads
- Dashboards and an ATT&CK view showing real attacker activity

```
Cowrie ─► CloudWatch Logs /honeypot/cowrie ─┬─► Lambda ─► S3 ─► Athena   (Phases 3–4, unchanged)
                                            │
                                            └─► Wazuh Manager (pull, every 5 min)
                                                   │ decode JSON → match rules → alert
                                                   ▼
                                                Wazuh Indexer ─► Wazuh Dashboard
```

> [!NOTE]
> Wazuh **pulls** from CloudWatch using its built-in AWS module (`aws-s3` wodle). That's why it can run on your laptop: no inbound ports are needed and the honeypot isn't touched.

---

## Part 0 — Concepts You Need First

Read these before you build anything. They're also what interviewers ask about.

| Concept | What it means in Wazuh | Our example |
|---|---|---|
| **Manager** | The brain. Receives logs, decodes them, runs rules, produces alerts | The `wazuh.manager` container |
| **Indexer** | Stores alerts so you can search them (it's OpenSearch, a fork of Elasticsearch) | `wazuh.indexer` container |
| **Dashboard** | Web UI on top of the indexer (OpenSearch Dashboards, similar to Kibana) | https://localhost |
| **Wodle** | A built-in module that collects data. `aws-s3` collects from AWS services | Pulls `/honeypot/cowrie` |
| **Decoder** | Turns a raw log line into named fields | Cowrie is JSON, so the built-in `json` decoder does it for free |
| **Rule** | "If the decoded fields match X, raise an alert at level N" | `eventid == cowrie.login.success` → level 10 |
| **Level** | Severity 0–15. Level 0 = never alert; 3+ is stored as an alert by default; 12+ is critical | Malware download = 13 |
| **Rule chaining (`if_sid`)** | A child rule only runs when its parent matched. This builds a tree | "command" → "command contains `crontab`" |
| **Correlation (`frequency`)** | Fire when a rule matched N times within T seconds, optionally for the same field | 10 failed logins from the same IP in 120 s = brute force |

The pipeline inside the manager is always **raw log → decoder → rules → alert (if level ≥ 3) → indexer → dashboard**.

---

## Part 1 — Create a Read-Only AWS Identity for Wazuh

Your laptop isn't an EC2 instance, so it can't use an IAM role. Instead we create an **IAM user** that can *only read the honeypot log group*. That's least privilege, just like the earlier phases.

The Terraform is already written: [`terraform/phase5.tf`](../terraform/phase5.tf). Read it and notice:

- `logs:DescribeLogGroups` needs `Resource = "*"`, because AWS doesn't support scoping it to one group
- The read actions are scoped to **one** log group ARN
- The secret key output is marked `sensitive`

```bash
cd terraform
terraform plan     # should show 3 new resources: user, policy, access key
terraform apply

terraform output wazuh_access_key_id
terraform output -raw wazuh_secret_access_key   # -raw prints the sensitive value
```

Keep these two values for Part 3. **Never commit them.**

> [!CAUTION]
> The secret is stored in `terraform.tfstate`. It's git-ignored, but treat that file as a secret too.

---

## Part 1.5 — Free Mode on a Low-RAM Laptop (8 GB or less)

The full Wazuh stack wants about 8 GB of RAM just for Docker. On an 8 GB laptop, learn in **two stages**:

| Stage | What runs | RAM | What you learn |
|---|---|---|---|
| **1. Manager only** | `wazuh.manager` | ~0.6 GB | AWS ingestion, decoders, writing and testing rules (Parts 3–4). This is most of the real SIEM skill |
| **2. Full stack** | manager + indexer + dashboard | ~3.5 GB (with tuning) | Dashboards and the ATT&CK view (Part 5) |

### Cap WSL memory so Windows stays usable

Create `C:\Users\<you>\.wslconfig`:

```ini
[wsl2]
memory=4GB
swap=6GB
```

Then run `wsl --shutdown` and restart Docker Desktop.

### Stage 1: run the manager on its own

Use [`wazuh/docker-compose.manager-only.yml`](../wazuh/docker-compose.manager-only.yml) instead of Part 2. Put your `aws-credentials` file (Part 3.1) in the `wazuh/` folder; it's git-ignored. Then:

```powershell
cd wazuh
docker compose -f docker-compose.manager-only.yml up -d
docker compose -f docker-compose.manager-only.yml exec wazuh.manager /var/ossec/bin/wazuh-logtest
```

With no dashboard, read alerts straight from the file:

```powershell
docker compose -f docker-compose.manager-only.yml exec wazuh.manager tail -f /var/ossec/logs/alerts/alerts.json
```

To add the AWS module (Part 3.2) in Stage 1:
1. Copy the config out of the container:
   ```powershell
   docker compose -f docker-compose.manager-only.yml cp wazuh.manager:/var/ossec/etc/ossec.conf ./ossec.conf
   ```
2. Paste the wodle block into `ossec.conf`.
3. Copy it back in and restart the manager:
   ```powershell
   docker compose -f docker-compose.manager-only.yml cp ./ossec.conf wazuh.manager:/var/ossec/etc/ossec.conf
   docker compose -f docker-compose.manager-only.yml restart
   ```

### Stage 2: full stack with tuned memory

Follow Part 2, but before `docker compose up -d`, edit `single-node/docker-compose.yml` and set the indexer heap to 512 MB:

```yaml
  wazuh.indexer:
    environment:
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"
```

Stop the Stage 1 container first, and close heavy apps (browsers with many tabs, IDEs) while the stack runs.

### Keeping AWS at $0

| Item | Free? |
|---|---|
| IAM user, policy, access key | Always free |
| CloudWatch Logs | Free tier: 5 GB ingestion/storage per month, far more than a honeypot produces |
| Lambda, S3, Athena at honeypot scale | Free tier, or a few cents |
| **Honeypot EC2 t3.micro** | **Only free under the AWS Free Tier** (750 hrs/month on older accounts, or the credits on newer ones). Check **Billing → Free Tier** in the console. Otherwise, stop the instance when you're not studying |
| Elastic IP | Don't add one: an unattached Elastic IP costs money |

---

## Part 2 — Run Wazuh in Docker

### 2.1 Requirements

- Docker Desktop (WSL2 backend on Windows)
- **At least 8 GB RAM free for Docker.** The indexer is memory-hungry. Check Docker Desktop → Settings → Resources

### 2.2 Raise `vm.max_map_count` (indexer requirement)

OpenSearch refuses to start if this kernel setting is too low.

```powershell
# Windows (Docker Desktop / WSL2). Resets on reboot, so re-run it after restarting.
wsl -d docker-desktop sysctl -w vm.max_map_count=262144
```

```bash
# Linux
sudo sysctl -w vm.max_map_count=262144
```

### 2.3 Get the official Wazuh Docker deployment

Clone it **outside** this repo, because it's a separate project:

```bash
cd D:\Projects
git clone https://github.com/wazuh/wazuh-docker.git
cd wazuh-docker
git tag --list "v4.*"          # pick the newest 4.x tag
git checkout v4.X.Y            # replace with that tag
cd single-node
```

### 2.4 Generate TLS certificates, then start

Wazuh components talk to each other over TLS, so certificates come first:

```bash
docker compose -f generate-indexer-certs.yml run --rm generator
docker compose up -d
docker compose ps              # wait until all 3 containers are "running"
```

Open **https://localhost**, accept the self-signed certificate warning, and log in with `admin` / `SecretPassword` (the defaults are in `docker-compose.yml`; change them for anything other than local use).

📸 **Screenshot:** the empty Wazuh dashboard → `screenshots/wazuh_first_login.png`

---

## Part 3 — Connect Wazuh to CloudWatch

### 3.1 Give the manager the AWS credentials

Create a file called `aws-credentials` in `wazuh-docker/single-node/`:

```ini
[wazuh]
aws_access_key_id = AKIA...from-terraform-output
aws_secret_access_key = ...from-terraform-output
region = us-east-1
```

Mount it into the manager. In `docker-compose.yml`, under `wazuh.manager:` → `volumes:`, add:

```yaml
      - ./aws-credentials:/root/.aws/credentials:ro
```

`:ro` means read-only: even the container can't modify it.

### 3.2 Enable the AWS module

Open `single-node/config/wazuh_cluster/wazuh_manager.conf`. Paste the block from [`wazuh/aws_cloudwatch_wodle.xml`](../wazuh/aws_cloudwatch_wodle.xml) **inside** the `<ossec_config>` element.

What each setting does:

| Setting | Why |
|---|---|
| `<interval>5m</interval>` | How often Wazuh polls CloudWatch. Lower means faster alerts but more API calls |
| `<aws_profile>wazuh</aws_profile>` | Matches the `[wazuh]` section in the credentials file |
| `<aws_log_groups>` | The group your CloudWatch Agent writes to in Phase 2 |
| `<only_logs_after>` | On the first run, backfill everything since this date so you have data immediately |

### 3.3 Restart and check the logs

```bash
docker compose down
docker compose up -d
docker compose exec wazuh.manager tail -f /var/ossec/logs/ossec.log | grep -i aws
```

You want to see the module start without credential or `AccessDenied` errors.

---

## Part 4 — Write Detection Rules

This is the most important part of the phase. Open [`wazuh/cowrie_rules.xml`](../wazuh/cowrie_rules.xml) and read it top to bottom alongside this table:

| Rule | Level | Logic | ATT&CK |
|---|---|---|---|
| 100100 | 0 | Base: `eventid` starts with `cowrie.`. Never alerts on its own; it's the parent of everything | — |
| 100101 | 3 | New connection | — |
| 100102 | 5 | Failed login | T1110 Brute Force |
| 100103 | 10 | **Correlation:** 100102 ×10 from the *same* `src_ip` within 120 s | T1110.001 Password Guessing |
| 100104 | 10 | Successful login (Cowrie accepts weak creds) | T1078 Valid Accounts |
| 100110 | 6 | Any command typed | T1059.004 Unix Shell |
| 100111 | 7 | ↳ command contains `uname`, `nproc`, ... | T1082 System Info Discovery |
| 100112 | 12 | ↳ command touches `authorized_keys` | T1098.004 SSH Authorized Keys |
| 100113 | 12 | ↳ `crontab` / `/etc/cron` | T1053.003 Cron |
| 100114 | 12 | ↳ `xmrig`, `stratum+tcp`, ... | T1496 Resource Hijacking |
| 100115 | 10 | ↳ `wget` / `curl` / `tftp` | T1105 Ingress Tool Transfer |
| 100120 | 13 | File actually downloaded | T1105 Ingress Tool Transfer |

**Why the tree matters:** Wazuh tries child rules after a parent matches, and the deepest matching child wins. A command like `echo ssh-rsa ... >> ~/.ssh/authorized_keys` matches 100110 (command) first, then 100112 (persistence), so you get one level-12 alert instead of a generic level-6 one.

### 4.1 Install the rules

```bash
# from wazuh-docker/single-node
docker compose cp D:/Projects/cloud-siem-honeypot/wazuh/cowrie_rules.xml wazuh.manager:/var/ossec/etc/rules/cowrie_rules.xml
docker compose exec wazuh.manager chown wazuh:wazuh /var/ossec/etc/rules/cowrie_rules.xml
docker compose exec wazuh.manager /var/ossec/bin/wazuh-control restart
```

> [!NOTE]
> On older 4.x images the group may be `ossec` instead of `wazuh`. If `chown` fails, use `wazuh:ossec` or `root:wazuh`.

### 4.2 Test rules with `wazuh-logtest` (do this every time you edit a rule)

`wazuh-logtest` lets you paste a log line and see which decoder and rule match it, without waiting for real attackers.

```bash
docker compose exec wazuh.manager /var/ossec/bin/wazuh-logtest
```

Paste each of these lines one at a time:

```json
{"eventid":"cowrie.login.success","username":"root","password":"123456","src_ip":"203.0.113.5","session":"a1b2c3","timestamp":"2026-10-11T10:00:00.000Z"}
{"eventid":"cowrie.command.input","input":"cd ~; echo ssh-rsa AAAA >> .ssh/authorized_keys","src_ip":"203.0.113.5","session":"a1b2c3","timestamp":"2026-10-11T10:00:05.000Z"}
{"eventid":"cowrie.session.file_download","url":"http://198.51.100.9/x.sh","shasum":"abc123","src_ip":"203.0.113.5","session":"a1b2c3","timestamp":"2026-10-11T10:00:09.000Z"}
```

Expected output for the second line:

```
**Phase 2: Completed decoding.
        name: 'json'
        eventid: 'cowrie.command.input'
        input: 'cd ~; echo ssh-rsa AAAA >> .ssh/authorized_keys'
        ...
**Phase 3: Completed filtering (rules).
        id: '100112'
        level: '12'
        description: 'Cowrie: SSH key persistence attempt from 203.0.113.5'
        mitre.technique: '['SSH Authorized Keys']'
**Alert to be generated.
```

To test the brute-force correlation, paste a `cowrie.login.failed` line with the same `src_ip` 10 times. The 10th one should match **100103**.

📸 **Screenshot:** a logtest run showing rule 100112 → `screenshots/wazuh_logtest.png`

---

## Part 5 — See Real Alerts

Wait one or two polling intervals, or rely on the backfill. Then in the dashboard:

1. **Threat Hunting** (called *Security events* in older versions): filter with `rule.groups: cowrie`
2. Add columns: `data.src_ip`, `data.username`, `data.input`, `rule.description`, `rule.level`
3. **MITRE ATT&CK** module: you should see T1110, T1078, T1059 and others light up. This is the screenshot recruiters remember

Useful queries in the search bar (DQL):

```
rule.groups: cowrie and rule.level >= 10
rule.id: 100103
data.eventid: "cowrie.command.input" and data.input: *wget*
```

### 5.1 Build a dashboard

Go to **☰ → Dashboards → Create new** and add these visualizations, using index pattern `wazuh-alerts-*`:

| Visualization | Type | Config |
|---|---|---|
| Alerts over time | Area | X = `@timestamp`, split by `rule.level` |
| Top attacker IPs | Data table | Terms `data.src_ip`, size 10 |
| Top usernames tried | Tag cloud / bar | Terms `data.username` |
| Top passwords tried | Data table | Terms `data.password` |
| ATT&CK techniques | Pie | Terms `rule.mitre.technique` |
| Critical alerts | Saved search | `rule.groups: cowrie and rule.level >= 12` |

Save it as **"Cowrie Honeypot Overview"**.

📸 **Screenshots:** `wazuh_dashboard.png`, `wazuh_mitre.png`, `wazuh_alert_detail.png`

---

## Part 6 — Stretch Goals (pick any)

1. **GeoIP map.** Wazuh's ingest pipeline only geolocates its own field names (like `data.srcip`), not Cowrie's `data.src_ip`. Add a `geoip` processor for `data.src_ip` to the Filebeat pipeline in the manager (`/usr/share/filebeat/module/wazuh/alerts/ingest/pipeline.json`), then reload it with `filebeat setup --pipelines --modules wazuh`. After that, build a Coordinate Map visualization.
2. **Slack alerts.** Add an `<integration>` block with `<name>slack</name>`, your webhook URL and `<level>12</level>` to `wazuh_manager.conf`. You'll get a Slack message for every persistence attempt or malware download.
3. **VirusTotal.** Wazuh has a built-in `virustotal` integration. Look up `data.shasum` from rule 100120.
4. **Write your own rule:** detect `cat /etc/passwd` or `cat /etc/shadow` (T1003.008), test it in logtest, and add it to the table above.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Indexer container keeps restarting | `vm.max_map_count` too low (Part 2.2) or not enough RAM for Docker |
| `ossec.log` says `AccessDenied` | Wrong profile name, credentials file not mounted, or the IAM policy region/log group doesn't match |
| `ossec.log` says `No credentials` | The mount path must be exactly `/root/.aws/credentials` |
| Logtest shows `json` decoder but no `cowrie` rule | Rules file not in `/var/ossec/etc/rules/`, wrong permissions, or the manager wasn't restarted |
| Manager won't start after editing rules | XML syntax error. Check `ossec.log`; logtest also reports the bad line |
| No new alerts | Is Cowrie still running? Check `/honeypot/cowrie` in CloudWatch first. Then wait at least 5 minutes (polling interval) |

---

## What to Put on Your CV

> Integrated a cloud honeypot with **Wazuh SIEM**, pulling telemetry from AWS CloudWatch via a least-privilege IAM identity, and authored **12 custom detection rules** (including time-window brute-force correlation) mapped to **MITRE ATT&CK** techniques T1110, T1078, T1059, T1098, T1053, T1105 and T1496.

## Cleanup

```bash
# stop Wazuh (keeps data)
docker compose down
# delete Wazuh and all its data
docker compose down -v
# remove the IAM user: delete terraform/phase5.tf, then
terraform apply
```
