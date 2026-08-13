# Cloud SIEM Honeypot Lab

Welcome to the Cloud SIEM Honeypot Lab! This project is a fully automated, cloud-based threat intelligence gathering environment.

## 🚀 Overview
The goal of this project is to build a highly interactive SSH/Telnet honeypot that safely captures attacker activity from the public internet. The data collected by this honeypot is intended to be normalized and forwarded to a SIEM (Security Information and Event Management) platform for threat intelligence and visualization.

## 🛠️ Technology Stack
- **Infrastructure as Code**: Terraform
- **Cloud Provider**: AWS (Virtual Private Cloud, EC2, Security Groups)
- **Honeypot**: Cowrie (Medium-to-high interaction SSH/Telnet honeypot)
- **Log Processing**: Python

## 🏗️ Project Structure
- `terraform/`: Contains all AWS infrastructure configurations.
- `scripts/`: Shell and Python scripts for installing Cowrie and processing logs.
- `docs/`: Documentation, including our Threat Model and Architecture.

## 🔐 Security & Threat Model
This honeypot is designed with a strict blast-radius containment strategy:
- The EC2 instance is deployed in an isolated VPC with no peering to production environments.
- Real admin SSH access (Port 22) is restricted strictly to the operator's IP address.
- Cowrie runs as a low-privileged user to prevent privilege escalation.
- Zero real AWS credentials or sensitive data are stored on the host.
