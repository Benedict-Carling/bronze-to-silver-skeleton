#!/bin/bash -ue
set -euo pipefail

# 1. Check if azcopy is installed
if ! command -v azcopy >/dev/null 2>&1; then
    echo "❌ Error: 'azcopy' CLI tool is not installed or not found in PATH."
    echo "Please install azcopy (https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-v10) or run with '-profile docker'."
    exit 1
fi

# 2. Check SAS env file
if [ ! -f "azure_sas.env" ]; then
    echo "❌ Error: SAS environment file 'azure_sas.env' not found."
    exit 1
fi

. "azure_sas.env"

ID="20260727-mighty-guppy-74d0"
if [ -z "$ID" ]; then
    echo "❌ Error: Target dataset ID is empty."
    exit 1
fi

BLOB_URL="https://${AZURE_ACCOUNT}.blob.core.windows.net/${AZURE_CONTAINER}/${ID}"

echo "Downloading from: ${BLOB_URL}"

# 3. Download target dataset via azcopy.
#    azcopy recreates the source prefix inside the destination, so copying
#    into '.' yields ./<ID>/... Copying into '<ID>/' would nest as <ID>/<ID>/.
azcopy copy \
    "${BLOB_URL}?${AZURE_SAS}" \
    "." \
    --recursive \
    --log-level=INFO \
    --overwrite=true \
    > azcopy.log 2>&1 || {
        echo "❌ Error: azcopy download failed for dataset '${ID}'. See log output below:"
        cat azcopy.log
        exit 1
    }
