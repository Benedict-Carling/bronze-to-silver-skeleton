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

ID="20260727-mighty-guppy-74d0-silver"
if [ -z "$ID" ]; then
    echo "❌ Error: Upload ID is empty."
    exit 1
fi

# Nextflow stages the dataset as a symlink, and azcopy would copy the link
# rather than its contents. Resolve it on the host at submission time --
# Nextflow bind-mounts the resolved location into the container under the
# same absolute path, so this is valid on both the local and docker profiles.
REAL_PATH="/Users/benedictcarling/Documents/GitHub/lbf-upload/bronze-to-silver-skeleton/work/04/879da1c5985bd87a57ba36f9e4f17e/20260727-mighty-guppy-74d0"

if [ ! -e "$REAL_PATH" ]; then
    echo "❌ Error: Local source path '$REAL_PATH' does not exist."
    exit 1
fi

BLOB_PATH="https://${AZURE_ACCOUNT}.blob.core.windows.net/${AZURE_CONTAINER}/${ID}"

if [ -d "$REAL_PATH" ]; then
    TARGET_DEST="${BLOB_PATH}"
else
    TARGET_DEST="${BLOB_PATH}/$(basename "$REAL_PATH")"
fi

# 3. Upload data payload to Azure Blob Storage via azcopy
azcopy copy \
    "$REAL_PATH" \
    "${TARGET_DEST}?${AZURE_SAS}" \
    --recursive=true \
    --overwrite=false \
    --exclude-pattern=".DS_Store;._*" \
    > azcopy.log 2>&1 || {
        echo "❌ Error: azcopy data transfer failed. See log output below:"
        cat azcopy.log
        exit 1
    }

# 4. Upload the pre-generated sidecar ro-crate-metadata.json, resolved the same way.
azcopy copy \
    "/Users/benedictcarling/Documents/GitHub/lbf-upload/bronze-to-silver-skeleton/work/6a/342f1dbaa902bfd360359ec459d112/ro-crate-metadata.json" \
    "${BLOB_PATH}/ro-crate-metadata.json?${AZURE_SAS}" \
    --overwrite=true \
    >> azcopy.log 2>&1 || {
        echo "❌ Error: Failed to upload sidecar ro-crate-metadata.json via azcopy. See log output below:"
        cat azcopy.log
        exit 1
    }

echo "${BLOB_PATH}"
