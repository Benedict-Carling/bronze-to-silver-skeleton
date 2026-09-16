#!/bin/bash -ue
set -euo pipefail

if [ ! -f "azure_sas.env" ]; then
    echo "Error: SAS environment file 'azure_sas.env' not found."
    exit 1
fi

. "azure_sas.env"

if [ -z "20260727-mighty-guppy-74d0-silver" ]; then
    echo "Error: dataset id is empty."
    exit 1
fi

# The payload is staged as a symlink; the crate records and walks the real
# path, which Nextflow bind-mounts under the same location in containers.
rocrate_generator.py \
    --upload-id '20260727-mighty-guppy-74d0-silver' \
    --grade 'silver' \
    --blob-path '20260727-mighty-guppy-74d0-silver' \
    --uploaded-by "${USER_IDENTITY:-unknown}" \
    --subscription-name "${SUBSCRIPTION_NAME:-unknown}" \
    --subscription-id "${SUBSCRIPTION_ID:-unknown}" \
    --storage-account "$AZURE_ACCOUNT" \
    --container "$AZURE_CONTAINER" \
    --source-path '/Users/benedictcarling/Documents/GitHub/lbf-upload/bronze-to-silver-skeleton/work/04/879da1c5985bd87a57ba36f9e4f17e/20260727-mighty-guppy-74d0' \
    --derived-from '20260727-mighty-guppy-74d0' --property 'sample_id=SAM-9999' --conforms-to 'https://github.com/ImperialCollegeLondon/bronze-to-silver-skeleton/tree/main/profiles/minimal-silver'
