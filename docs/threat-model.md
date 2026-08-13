# Threat Model

| Question | Answer for this lab |
|---|---|
| **What assets exist?** | EC2 instance, its IP, Cowrie logs |
| **What are we protecting?** | Nothing real — this is a sacrificial host |
| **Who are the threat actors?** | Automated scanners, script kiddies, bot nets |
| **What data is allowed on this host?** | Only synthetic/fake credentials in Cowrie config |
| **What is NOT allowed?** | Real AWS creds, personal data, prod secrets |
| **Blast radius if compromised?** | Zero — dedicated VPC, no peering, no prod access |

> **Golden rule**: The EC2 instance must have **zero access** to your AWS account beyond its own VPC. Use a dedicated IAM role with no permissions, or no role at all.
