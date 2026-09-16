#!/bin/bash -ue
set -euo pipefail

    # 1. Verify Azure CLI installation
    if ! command -v az >/dev/null 2>&1; then
        echo "❌ Error: Azure CLI ('az') is not installed or not in PATH."
        echo "Please install Azure CLI (https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) to proceed."
        exit 1
    fi

    # 2. Verify input parameters
    if [ -z "bronze" ]; then
        echo "❌ Error: Target container name is required."
        exit 1
    fi

    if [ -z "role=bronze" ]; then
        echo "❌ Error: Storage account tag filter (e.g., 'role=bronze') is required."
        exit 1
    fi

    # 3. Verify Azure CLI login status & active subscription.
    #
    #    This is the first Azure call, so it is where a Conditional Access
    #    block, an expired refresh token and an unreadable ~/.azure all land.
    #    Azure distinguishes them precisely and we must not: answering every one
    #    of them with "run az login" sends a user whose sign-in was refused by
    #    policy to do the one thing that cannot help.
    set +e
    ACCOUNT_INFO=$(az account show -o json 2>az_login_err.txt)
    AZ_RC=$?
    set -e

    if [ "$AZ_RC" -ne 0 ] || [ -z "$ACCOUNT_INFO" ]; then
        echo "❌ Error: Could not read your Azure login state."
        if [ -s az_login_err.txt ]; then
            echo "--- Azure CLI reported: ---"
            cat az_login_err.txt
            echo "---------------------------"
        fi
        echo "If that message mentions a restricted location, device or authentication"
        echo "flow, this is Conditional Access refusing the sign-in, and running"
        echo "'az login' here will not fix it. Mint the credential on a machine where"
        echo "login works and use --sas_env instead. See docs/HPC.md."
        echo "Otherwise, run 'az login' and try again."
        exit 1
    fi

    # Parsed from the single response above rather than by re-invoking az three
    # more times: fewer calls, and no further places for an error to be lost.
    USER_NAME=$(printf '%s' "$ACCOUNT_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('user',{}).get('name',''))")
    SUB_NAME=$(printf '%s' "$ACCOUNT_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))")
    SUB_ID=$(printf '%s' "$ACCOUNT_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))")

    if [ -z "$SUB_ID" ]; then
        echo "❌ Error: No active Azure subscription found. Set one with 'az account set --subscription <ID>'."
        exit 1
    fi

    # 4. Auto-discover Storage Account using tag filter (role=bronze)
    TAG_FILTER="role=bronze"
    TAG_KEY="${TAG_FILTER%%=*}"
    TAG_VAL="${TAG_FILTER#*=}"

    if [ -z "$TAG_KEY" ] || [ -z "$TAG_VAL" ] || [ "$TAG_KEY" = "$TAG_FILTER" ]; then
        echo "❌ Error: Invalid tag filter format 'role=bronze'. Expected format: key=value (e.g. role=bronze)."
        exit 1
    fi

    # Branch on the exit code, not on whether the output was empty. Those are
    # different failures with opposite remedies: no rows means the tag really is
    # absent, whereas a failed call means we never got to look. Conflating them
    # sends the user to their Azure administrator to add a tag already there.
    set +e
    MATCHING_ACCOUNTS=$(az storage account list \
        --query "[?tags.${TAG_KEY}=='${TAG_VAL}'].name" \
        -o tsv 2>az_list_err.txt | tr -d '')
    AZ_RC=$?
    set -e

    if [ "$AZ_RC" -ne 0 ]; then
        echo "❌ Error: Azure CLI failed while listing storage accounts in subscription '$SUB_NAME' ($SUB_ID)."
        if [ -s az_list_err.txt ]; then
            echo "--- Azure CLI reported: ---"
            cat az_list_err.txt
            echo "---------------------------"
        fi
        echo "This is an access or connectivity problem, not a tagging problem."
        exit 1
    fi

    MATCHING_ACCOUNTS=$(echo "$MATCHING_ACCOUNTS" | grep -v '^[[:space:]]*$' || true)

    COUNT=0
    if [ -n "$MATCHING_ACCOUNTS" ]; then
        COUNT=$(echo "$MATCHING_ACCOUNTS" | grep -c '^.' || echo 0)
    fi

    if [ "$COUNT" -eq 0 ]; then
        echo "❌ Error: No storage account tagged with 'role=bronze' was found in subscription '$SUB_NAME' ($SUB_ID)."
        echo "Please ask your Azure administrator to apply tag 'role=bronze' to the target storage account in this subscription."
        exit 1
    elif [ "$COUNT" -gt 1 ]; then
        echo "❌ Ambiguity Error: Found $COUNT storage accounts tagged with 'role=bronze' in subscription '$SUB_NAME':"
        echo "$MATCHING_ACCOUNTS"
        echo "Exactly ONE storage account per subscription must be tagged with 'role=bronze'. Please resolve the tagging conflict."
        exit 1
    fi

    STORAGE_ACCOUNT="$MATCHING_ACCOUNTS"

    # 5. Calculate expiration timestamp. Python's datetime avoids branching on
    #    GNU vs BSD date flags. Callers bound `hours` to 1..168.
    set +e
    EXPIRY=$(python3 -c "from datetime import datetime, timedelta, timezone; print((datetime.now(timezone.utc) + timedelta(hours=168)).strftime('%Y-%m-%dT%H:%M:%SZ'))" 2>expiry_err.txt)
    PY_RC=$?
    set -e

    if [ "$PY_RC" -ne 0 ] || [ -z "$EXPIRY" ]; then
        echo "❌ Error: Failed to calculate the SAS expiry timestamp."
        if [ -s expiry_err.txt ]; then
            echo "--- python3 reported: ---"
            cat expiry_err.txt
            echo "-------------------------"
        fi
        exit 1
    fi

    # 6. Mint User Delegation SAS token for the target container
    set +e
    AZURE_SAS=$(az storage container generate-sas \
        --auth-mode login \
        --as-user \
        --account-name "$STORAGE_ACCOUNT" \
        --name "bronze" \
        --permissions "racwdl" \
        --expiry "$EXPIRY" \
        --https-only \
        --output tsv 2>az_sas_err.txt | tr -d '')
    AZ_RC=$?
    set -e

    if [ "$AZ_RC" -ne 0 ] || [ -z "$AZURE_SAS" ]; then
        echo "❌ Error: Failed to mint SAS token for container 'bronze' on account '$STORAGE_ACCOUNT'."
        if [ -s az_sas_err.txt ]; then
            echo "--- Azure CLI reported: ---"
            cat az_sas_err.txt
            echo "---------------------------"
        fi
        echo "Minting a SAS needs the 'Storage Blob Delegator' role assigned at the STORAGE"
        echo "ACCOUNT scope -- not at container scope. Getting a user delegation key is an"
        echo "account-level operation, so a container-scoped role cannot authorise it."
        echo "See docs/HPC.md for the exact role assignment."
        exit 1
    fi

    # 7. Write credentials. umask first so the token is never briefly
    #    world-readable.
    umask 077
    cat > azure_sas.env <<EOF
AZURE_ACCOUNT='$STORAGE_ACCOUNT'
AZURE_CONTAINER='bronze'
AZURE_SAS='${AZURE_SAS}'
AZURE_SAS_EXPIRY='$EXPIRY'
AZURE_SAS_PERMISSIONS='racwdl'
USER_IDENTITY='$USER_NAME'
SUBSCRIPTION_NAME='$SUB_NAME'
SUBSCRIPTION_ID='$SUB_ID'
EOF
    chmod 600 azure_sas.env
