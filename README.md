# bronze-to-silver-skeleton

The smallest pipeline that turns a bronze dataset into a silver one. It downloads
a bronze dataset, records a few PropertyValues on it, and publishes the result
to the silver container through the `PUBLISH` subworkflow of
[amrproj-data-management](https://github.com/ImperialCollegeLondon/amrproj-data-management),
included here as a submodule.

```bash
git submodule update --init
echo '{"sample_id": "SAM-0001"}' > metadata.json
nextflow run main.nf --target_id 20260805-empty-ds --metadata metadata.json -profile docker
```

Parameters are declared in `schemas/main.json`. Pass `--sas_env` and
`--download_sas_env` to run without an `az login` on the machine, exactly as
`docs/HPC.md` in the submodule describes.

## Profiles

`profiles/minimal-silver` requires a `sample_id` PropertyValue.
`profiles/extended-silver` builds on it (`prof:isProfileOf`) and additionally
requires `experiment_type`. Select one with `--profile`. To extend further, add
a directory under `profiles/` whose `profile.ttl` names its parent and whose
`must/` holds the extra SHACL shapes.
