# Platform Engineering Toolbox

This repository is a collection of useful tools, scripts, and practices designed to reduce friction for users and developers. It serves as an evolving resource for platform engineering teams to build, manage, and share internal tools.

## Available Tools

### [GCP Workstation Manager](./gcp-workstation-manager)
A simple bash-based CLI tool to list, start, stop, restart, and tunnel to Google Cloud Workstations. It eliminates the need to type out long `gcloud` commands with repetitive flags and provides an interactive setup to discover your regions, clusters, and configurations.

**Key Features:**
- Interactive configuration setup
- Start/stop/restart individual workstations
- Automatically start a workstation and establish an SSH/TCP tunnel for IDE connectivity (e.g., VS Code)
