# Google Cloud Workstations CLI Manager

A simple bash-based CLI tool to list, start, stop, restart, and tunnel to Google Cloud Workstations without having to type out long `gcloud` commands with repetitive flags.

## Prerequisites

- [Google Cloud CLI (`gcloud`)](https://cloud.google.com/sdk/docs/install) installed and authenticated (`gcloud auth login`).
- Appropriate IAM permissions to view and manage Google Cloud Workstations.

## Setup

The easiest way to configure the CLI is using the interactive setup command. It will discover your regions, clusters, and configurations for you.

1. Ensure the script is executable:
   ```bash
   chmod +x workstation.sh
   ```
2. Run the interactive setup:
   ```bash
   ./workstation.sh setup
   ```
   *This will prompt you to select your Project ID, Region, Cluster, and Config, and will save them to a `.env` file (either in the script directory or your home directory).*

Alternatively, you can manually configure it:
1. Copy `.env.example` to `.env`.
2. Edit `.env` and fill in your GCP configuration (`PROJECT_ID`, `REGION`, `CLUSTER`, `CONFIG`).

## Usage

```bash
./workstation.sh {setup|list|start|stop|restart|tunnel|version} [WORKSTATION_NAME]
```

### Commands

#### Interactive Setup
Interactively discover and configure your workstation settings.
```bash
./workstation.sh setup
```

#### List Workstations
Lists all workstations across all regions and configurations within your configured project.
```bash
./workstation.sh list
```

#### Start a Workstation
Starts a specific workstation by name.
```bash
./workstation.sh start my-workstation-name
```

#### Stop a Workstation
Stops a specific workstation by name.
```bash
./workstation.sh stop my-workstation-name
```

#### Restart a Workstation
Stops and then starts a specific workstation by name.
```bash
./workstation.sh restart my-workstation-name
```

#### Tunnel to a Workstation (e.g., for VSCode)
Starts a TCP tunnel to the workstation on a local port. If the workstation is not currently running, it will automatically start it first. Useful for connecting local VSCode to the remote workstation via SSH.
```bash
./workstation.sh tunnel my-workstation-name [LOCAL_PORT]
```
*(Default LOCAL_PORT is 2222)*

#### Version
Displays the current version of the script.
```bash
./workstation.sh version
```