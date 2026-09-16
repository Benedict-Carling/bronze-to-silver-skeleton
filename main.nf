nextflow.enable.dsl=2

include { validateParameters; paramsSummaryLog } from 'plugin/nf-schema'

include { readSasEnv }     from './amrproj-data-management/nf_modules/sas_env'
include { MINT_SAS }       from './amrproj-data-management/nf_modules/mint_sas'
include { AZURE_DOWNLOAD } from './amrproj-data-management/nf_modules/azcopy_download'
include { PUBLISH }        from './amrproj-data-management/nf_modules/publish'

def helpMessage() {
    log.info """
    ================================================================
    Bronze to Silver Skeleton Pipeline
    ================================================================
    Retrieves a dataset from bronze, adds metadata, and lands it in silver.

    Usage:
      nextflow run main.nf --target_id <id> --metadata <file.json> [options]

    Required:
      --target_id ID             ID of the bronze dataset (e.g. 20260723-swift-falcon-8a2b)
      --metadata FILE            JSON object of PropertyValues to record, e.g. {"sample_id": "SAM-1"}

    Optional:
      --profile NAME             Directory under profiles/ to validate against (default minimal-silver)
      --sas_env FILE             Pre-minted credential for the silver container (write)
      --download_sas_env FILE    Pre-minted credential for the bronze container (read)
      -profile NEXTFLOW_PROFILE  'local' (default) or 'docker'

    Parameters are declared in schemas/main.json.
    ================================================================
    """
}

workflow {
    main:
        if (params.help) {
            helpMessage()
            exit 0
        }

        validateParameters(parameters_schema: 'schemas/main.json')
        log.info paramsSummaryLog(workflow, parameters_schema: 'schemas/main.json')

        def target_id = params.target_id.trim()
        def properties = new groovy.json.JsonSlurper().parse(file(params.metadata, checkIfExists: true))
        if (!(properties instanceof Map)) {
            log.error "--metadata must be a JSON object of name: value pairs"
            exit 1
        }

        download_sas = params.download_sas_env
            ? channel.of(['sas_meta', readSasEnv(params.download_sas_env, 'download', params.container)])
            : MINT_SAS(params.container, params.bronze_tag, 'rl', 168)

        download = AZURE_DOWNLOAD(download_sas.map { _meta, sas_env -> [target_id, sas_env] })

        payload = download.data_dir.map { _id, path -> ["${target_id}-silver".toString(), path] }

        def provenance = [
            derived_from: target_id,
            instruments : [[workflow.manifest.name, workflow.manifest.version, workflow.manifest.homePage]],
            properties  : properties.collectEntries { k, v -> [(k.toString()): v.toString()] },
        ]

        PUBLISH(payload, 'silver', "${projectDir}/profiles/${params.profile}", provenance)

    publish:
        upload_log = PUBLISH.out.azcopy_log
}

output {
    upload_log {
        path { id, _log_file -> "upload_logs/${id.trim()}" }
    }
}
