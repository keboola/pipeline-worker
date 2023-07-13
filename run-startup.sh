#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$WORKER_NAME" != "pipeline-"* ]] ;
then
  printf "'%s' is not a valid worker name (must match 'pipeline-*')." "$WORKER_NAME"
  exit 1
fi

printf "Running deployment of %s\n" "$WORKER_NAME"

az group create \
  --subscription "$SUBSCRIPTION" \
  --location "$WORKER_LOCATION" \
  --name "$WORKER_NAME" \
  --tags "purpose=azure-pipeline" "workerName=$WORKER_NAME"

az deployment group create \
    --subscription "$SUBSCRIPTION" \
    --resource-group "$WORKER_NAME" \
    --name "$WORKER_NAME" \
    --template-file ./template.json \
    --parameters \
        adminUsername="$ADMIN_USERNAME" \
        adminPassword="$ADMIN_PASSWORD"

vmId=$(
  az deployment group show \
    --subscription "$SUBSCRIPTION" \
    --resource-group "$WORKER_NAME" \
    --name "$WORKER_NAME" \
    --query "properties.outputs.vmId.value" \
    --output tsv
)

envsubst '${PAT_TOKEN} ${$WORKER_NAME} ${POOL_NAME}' < startup.sh > startup-replaced.sh
script_content=$(cat startup-replaced.sh | gzip -9 | base64 -w 0)

printf "\nRunning Startup script"
az vm extension set \
  --publisher "Microsoft.Azure.Extensions" \
  --name "CustomScript" \
  --version "2.0" \
  --ids "$vmId" \
  --protected-settings "{\"script\":\"$script_content\"}"
