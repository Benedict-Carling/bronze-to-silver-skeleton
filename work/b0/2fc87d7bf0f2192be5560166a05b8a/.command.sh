#!/bin/bash -ue
set -euo pipefail

    if ! command -v rocrate-validator >/dev/null 2>&1; then
        echo "Error: 'rocrate-validator' is not installed. Install requirements.txt or run with '-profile docker'."
        exit 1
    fi

    TOKEN=$(sed -n 's/.*prof:hasToken *"\([^"]*\)".*/\1/p' profiles/minimal-silver/profile.ttl | head -1)
    if [ -z "$TOKEN" ]; then
        echo "Error: profiles/minimal-silver/profile.ttl declares no prof:hasToken."
        exit 1
    fi

    # The crate is the payload plus its sidecar; rebuild that layout from the
    # real payload path so the validator sees every hasPart file.
    mkdir crate
    ln -s "/Users/benedictcarling/Documents/GitHub/lbf-upload/bronze-to-silver-skeleton/work/08/f96a3f0cdd69c88023207a6ed1ce56/20260727-mighty-guppy-74d0" "crate/20260727-mighty-guppy-74d0"
    cp "ro-crate-metadata.json" crate/ro-crate-metadata.json

    # The validator ignores symlinked profile directories, so copy the staged one.
    mkdir profile_src
    cp -RL "profiles/minimal-silver" profile_src/

    if rocrate-validator validate \
        --extra-profiles-path profile_src \
        --profile-identifier "$TOKEN" \
        --no-auto-profile \
        --requirement-severity required \
        --no-paging \
        --output-format json \
        --output-file validation-report.json \
        crate >validator.log 2>&1
    then
        echo "ro-crate-metadata.json conforms to profile '$TOKEN'."
    else
        if [ ! -s validation-report.json ]; then
            echo "Error: rocrate-validator could not run:"
            cat validator.log
            exit 1
        fi
        echo "Error: ro-crate-metadata.json does not conform to profile '$TOKEN':"
        python3 - <<'PY'
import json
report = json.load(open("validation-report.json"))
for issue in report.get("issues", []):
    print(f"  [{issue['check']['identifier']}] {issue['message']}")
PY
        exit 1
    fi
