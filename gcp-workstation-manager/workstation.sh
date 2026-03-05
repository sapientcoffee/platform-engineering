#!/usr/bin/env bash

# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Google Cloud Workstations CLI Manager
# Helper script to list, start, and stop Google Cloud Workstations.

VERSION="1.1.5"

set -e

# Get the directory of the script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Load environment variables if they exist (local takes precedence)
if [ -f "$HOME/.env" ]; then
    source "$HOME/.env"
fi
if [ -f "$DIR/.env" ]; then
    source "$DIR/.env"
fi

# Check for required commands
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud is not installed or not in PATH."
    exit 1
fi

# Function to show usage
usage() {
    echo "🚀 Google Cloud Workstations CLI Manager"
    echo ""
    echo "Usage: $0 {setup|list|start|stop|restart|tunnel|label|version} [WORKSTATION_NAME] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  setup                  ⚙️  Interactively configure project, region, cluster, and config."
    echo "  list                   📋 List all workstations across all regions and configurations in the project."
    echo "  start WORKSTATION_NAME ▶️  Start a specific workstation."
    echo "  stop WORKSTATION_NAME  🛑 Stop a specific workstation."
    echo "  restart WORKSTATION_NAME 🔄 Stop and then start a specific workstation."
    echo "  tunnel WORKSTATION_NAME [LOCAL_PORT] 🚇 Start a TCP tunnel (starts workstation if not running)."
    echo "  label WORKSTATION_NAME LABELS 🏷️  Apply labels (e.g., env=dev,desc=my-demo)."
    echo "  version                🏷️  Show the version of this script."
    echo ""
    echo "Required Configuration:"
    echo "  PROJECT_ID (via .env, environment variable, or active gcloud project)"
    exit 1
}

# Helper function to select an item from a list or provide a manual value
select_from_list() {
    local label=$1
    local items=$2
    local current_val=$3
    local __resultvar=$4
    local emoji=$5

    local item_array=()
    while IFS= read -r line; do
        [ -n "$line" ] && item_array+=("$line")
    done <<< "$items"

    local count=${#item_array[@]}

    if [ "$count" -gt 0 ]; then
        echo "$emoji Available $label:"
        local i=1
        for item in "${item_array[@]}"; do
            echo "  $i) $item"
            ((i++))
        done
        echo "  $i) ⌨️  [Manual Entry / Other]"
        
        read -p "👉 Select $label (1-$i) [1]: " selection
        selection=${selection:-1}

        if [[ "$selection" -ge 1 && "$selection" -lt "$i" ]]; then
            eval $__resultvar="'${item_array[$((selection-1))]}'"
            return 0
        fi
    fi

    read -p "⌨️  Enter $label [$current_val]: " manual_val
    eval $__resultvar="'${manual_val:-$current_val}'"
}

# Resolve workstation details (Region, Cluster, Config) automatically based on name
resolve_workstation_details() {
    local ws_name=$1
    
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    fi

    if [ -z "$PROJECT_ID" ]; then
        echo "❌ Error: PROJECT_ID could not be determined. Please run './workstation.sh setup', set it in .env, or set it via gcloud."
        exit 1
    fi

    echo "🔍 Looking up details for workstation '$ws_name' in project '$PROJECT_ID'..."
    local details
    details=$(gcloud workstations list --project="$PROJECT_ID" --filter="name:$ws_name" --format="value(name.segment(3), name.segment(5), name.segment(7))" 2>/dev/null)

    if [ -z "$details" ]; then
        echo "❌ Error: Workstation '$ws_name' not found in project '$PROJECT_ID'."
        exit 1
    fi

    # In case there are multiple matches (e.g. across regions), pick the first one
    details=$(echo "$details" | head -n 1)

    read -r REGION CLUSTER CONFIG <<< "$details"
}

COMMAND=$1
WORKSTATION_NAME=$2

if [ -z "$COMMAND" ]; then
    usage
fi

case "$COMMAND" in
    setup)
        echo "✨ --- Setup Cloud Workstations Configuration --- ✨"
        
        # 1. Project ID
        CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
        read -p "🔍 Enter PROJECT_ID [$CURRENT_PROJECT]: " INPUT_PROJECT
        PROJECT_ID=${INPUT_PROJECT:-$CURRENT_PROJECT}
        if [ -z "$PROJECT_ID" ]; then echo "❌ Error: PROJECT_ID is required."; exit 1; fi

        # 2. Region
        echo "🌐 Fetching regions with Cloud Workstations..."
        AVAILABLE_REGIONS=$(gcloud workstations clusters list --project="$PROJECT_ID" --region=- --format="value(REGION)" 2>/dev/null | sort -u)
        select_from_list "REGION" "$AVAILABLE_REGIONS" "" REGION "📍"
        if [ -z "$REGION" ]; then echo "❌ Error: REGION is required."; exit 1; fi

        # 3. Cluster
        echo "🏗️  Fetching clusters in region $REGION..."
        AVAILABLE_CLUSTERS=$(gcloud workstations clusters list --project="$PROJECT_ID" --region="$REGION" --format="value(name)" 2>/dev/null | awk -F/ '{print $NF}' | sort -u)
        select_from_list "CLUSTER" "$AVAILABLE_CLUSTERS" "" CLUSTER "🖥️ "
        if [ -z "$CLUSTER" ]; then echo "❌ Error: CLUSTER is required."; exit 1; fi

        # 4. Config
        echo "📝 Fetching configs for cluster $CLUSTER in region $REGION..."
        AVAILABLE_CONFIGS=$(gcloud workstations configs list --project="$PROJECT_ID" --region="$REGION" --cluster="$CLUSTER" --format="value(name)" 2>/dev/null | awk -F/ '{print $NF}' | sort -u)
        select_from_list "CONFIG" "$AVAILABLE_CONFIGS" "" CONFIG "⚙️ "
        if [ -z "$CONFIG" ]; then echo "❌ Error: CONFIG is required."; exit 1; fi

        # 5. Save location
        echo ""
        echo "💾 Where would you like to save this configuration?"
        echo "  1) 📂 Local directory ($DIR/.env)"
        echo "  2) 🏠 Home directory (~/.env)"
        read -p "👉 Select option (1/2) [1]: " SAVE_OPT

        if [ "$SAVE_OPT" == "2" ]; then
            ENV_FILE="$HOME/.env"
        else
            ENV_FILE="$DIR/.env"
        fi

        echo "✍️  Saving to $ENV_FILE..."
        
        touch "$ENV_FILE"

        update_env() {
            local key=$1
            local val=$2
            if grep -q "^${key}=" "$ENV_FILE"; then
                sed -i.bak "s|^${key}=.*|${key}=${val}|" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
            else
                echo "${key}=${val}" >> "$ENV_FILE"
            fi
        }

        update_env "PROJECT_ID" "$PROJECT_ID"
        update_env "REGION" "$REGION"
        update_env "CLUSTER" "$CLUSTER"
        update_env "CONFIG" "$CONFIG"

        echo "🎉 Configuration saved successfully!"
        ;;
    list)
        if [ -z "$PROJECT_ID" ]; then
            echo "❌ Error: PROJECT_ID is not set. Please run './workstation.sh setup' or set it in .env"
            exit 1
        fi
        echo "📋 Listing all workstations in project '$PROJECT_ID'..."
        gcloud workstations list \
            --project="$PROJECT_ID" \
            --format="table(name.basename():label=NAME, name.segment(3):label=REGION, name.segment(5):label=CLUSTER, name.segment(7):label=CONFIG, labels.env:label=ENV, labels.desc:label=DESC, state:label=STATE)" | awk '
            BEGIN {
                GREEN="\033[1;32m"
                RED="\033[1;31m"
                YELLOW="\033[1;33m"
                RESET="\033[0m"
            }
            NR==1 {print $0; next}
            {
                gsub(/STATE_RUNNING|RUNNING/, "🟢 " GREEN "&" RESET)
                gsub(/STATE_STOPPED|STOPPED/, "🔴 " RED "&" RESET)
                gsub(/STATE_STARTING|STARTING/, "⏳ " YELLOW "&" RESET)
                gsub(/STATE_STOPPING|STOPPING/, "🛑 " YELLOW "&" RESET)
                print
            }'
        ;;
    start)
        if [ -z "$WORKSTATION_NAME" ]; then
            echo "❌ Error: WORKSTATION_NAME is required for 'start'."
            usage
        fi
        resolve_workstation_details "$WORKSTATION_NAME"
        echo "▶️  Starting workstation '$WORKSTATION_NAME'..."
        gcloud workstations start "$WORKSTATION_NAME" \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --cluster="$CLUSTER" \
            --config="$CONFIG"
        ;;
    stop)
        if [ -z "$WORKSTATION_NAME" ]; then
            echo "❌ Error: WORKSTATION_NAME is required for 'stop'."
            usage
        fi
        resolve_workstation_details "$WORKSTATION_NAME"
        echo "🛑 Stopping workstation '$WORKSTATION_NAME'..."
        gcloud workstations stop "$WORKSTATION_NAME" \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --cluster="$CLUSTER" \
            --config="$CONFIG"
        ;;
    tunnel)
        if [ -z "$WORKSTATION_NAME" ]; then
            echo "❌ Error: WORKSTATION_NAME is required for 'tunnel'."
            usage
        fi
        LOCAL_PORT=${3:-2222}
        resolve_workstation_details "$WORKSTATION_NAME"
        
        echo "🔍 Checking status of workstation '$WORKSTATION_NAME'..."
        STATE=$(gcloud workstations describe "$WORKSTATION_NAME" \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --cluster="$CLUSTER" \
            --config="$CONFIG" \
            --format="value(state)" 2>/dev/null)
            
        if [ "$STATE" != "STATE_RUNNING" ]; then
            echo "▶️  Workstation is not running (State: ${STATE:-UNKNOWN}). Starting workstation '$WORKSTATION_NAME'..."
            gcloud workstations start "$WORKSTATION_NAME" \
                --project="$PROJECT_ID" \
                --region="$REGION" \
                --cluster="$CLUSTER" \
                --config="$CONFIG"
        fi
        
        echo "🚇 Starting TCP tunnel for '$WORKSTATION_NAME' on local port $LOCAL_PORT..."
        echo ""
        
        SSH_CONFIG_ENTRY="Host $WORKSTATION_NAME
    HostName localhost
    Port $LOCAL_PORT
    User user
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null"

        # Check if entry already exists (exact match for Host)
        if ! grep -Eq "^Host[[:space:]]+$WORKSTATION_NAME([[:space:]]|$)" "$HOME/.ssh/config" 2>/dev/null; then
            read -p "❓ Would you like to add this workstation to your ~/.ssh/config? (y/N): " ADD_SSH
            if [[ "$ADD_SSH" =~ ^[Yy]$ ]]; then
                mkdir -p "$HOME/.ssh"
                echo "" >> "$HOME/.ssh/config"
                echo "$SSH_CONFIG_ENTRY" >> "$HOME/.ssh/config"
                echo "✅ Added to ~/.ssh/config!"
                echo "✨ You can now connect in VSCode by selecting '$WORKSTATION_NAME' in the Remote-SSH menu."
                echo ""
            else
                echo "✨ To connect from VSCode:"
                echo "   1. Ensure 'Remote - SSH' extension is installed."
                echo "   2. Connect to: ssh user@localhost -p $LOCAL_PORT"
                echo ""
                echo "📝 Recommended ~/.ssh/config entry:"
                echo "$SSH_CONFIG_ENTRY"
                echo ""
            fi
        else
            echo "✅ Workstation '$WORKSTATION_NAME' is already in your ~/.ssh/config."
            echo "✨ You can connect in VSCode by selecting '$WORKSTATION_NAME' in the Remote-SSH menu."
            echo ""
        fi
        
        gcloud workstations start-tcp-tunnel "$WORKSTATION_NAME" 22 \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --cluster="$CLUSTER" \
            --config="$CONFIG" \
            --local-host-port=":$LOCAL_PORT"
        ;;
    label)
        if [ -z "$WORKSTATION_NAME" ]; then
            echo "❌ Error: WORKSTATION_NAME is required for 'label'."
            usage
        fi
        LABELS=$3
        if [ -z "$LABELS" ]; then
            echo "❌ Error: LABELS are required (e.g., env=dev,desc=demo)."
            usage
        fi

        # Sanitize labels for Google Cloud (lowercase, no spaces, hyphens/underscores only)
        # 1. Lowercase everything
        # 2. Replace spaces with hyphens
        # 3. Strip any other character not in a-z0-9,=_ or hyphen
        SANITIZED_LABELS=$(echo "$LABELS" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g' | sed 's/[^a-z0-9,=_-]//g')
        # Ensure it doesn't have double hyphens
        SANITIZED_LABELS=$(echo "$SANITIZED_LABELS" | sed 's/--/-/g')
        
        if [ "$LABELS" != "$SANITIZED_LABELS" ]; then
            echo "⚠️  Labels sanitized to meet Google Cloud requirements: '$SANITIZED_LABELS'"
            LABELS=$SANITIZED_LABELS
        fi

        resolve_workstation_details "$WORKSTATION_NAME"
        echo "🏷️  Applying labels '$LABELS' to workstation '$WORKSTATION_NAME'..."
        # Parse labels into JSON (e.g. from "env=dev,desc=demo" to '{"env":"dev","desc":"demo"}')
        JSON_LABELS=$(echo "$LABELS" | awk -F, 'BEGIN { printf "{" } {
            for(i=1; i<=NF; i++) {
                split($i, a, "=");
                printf "\"%s\":\"%s\"", a[1], a[2];
                if (i < NF) printf ",";
            }
        } END { printf "}" }')

        # Use REST API to update labels since gcloud workstations update does not exist
        TOKEN=$(gcloud auth print-access-token)
        RESPONSE=$(curl -s -X PATCH -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"labels\": $JSON_LABELS}" \
            "https://workstations.googleapis.com/v1/projects/$PROJECT_ID/locations/$REGION/workstationClusters/$CLUSTER/workstationConfigs/$CONFIG/workstations/$WORKSTATION_NAME?updateMask=labels")
        
        if echo "$RESPONSE" | grep -q "\"name\":"; then
            echo "✅ Labels applied successfully."
        else
            echo "❌ Failed to update labels. API response:"
            echo "$RESPONSE"
            exit 1
        fi
        ;;
    restart)
        if [ -z "$WORKSTATION_NAME" ]; then
            echo "❌ Error: WORKSTATION_NAME is required for 'restart'."
            usage
        fi
        resolve_workstation_details "$WORKSTATION_NAME"
        echo "🔄 Restarting workstation '$WORKSTATION_NAME'..."
        echo "🛑 Stopping workstation..."
        gcloud workstations stop "$WORKSTATION_NAME" \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --cluster="$CLUSTER" \
            --config="$CONFIG"
        echo "▶️  Starting workstation..."
        gcloud workstations start "$WORKSTATION_NAME" \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --cluster="$CLUSTER" \
            --config="$CONFIG"
        ;;
    version|-v|--version)
        echo "Google Cloud Workstations CLI Manager version $VERSION"
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'"
        usage
        ;;
esac
