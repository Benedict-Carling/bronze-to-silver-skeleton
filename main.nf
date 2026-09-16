nextflow.enable.dsl=2

include { MINT_SAS }        from './amrproj-data-management/nf_modules/mint_sas'
include { AZURE_DOWNLOAD }  from './amrproj-data-management/nf_modules/azcopy_download'
include { PUBLISH }         from './amrproj-data-management/nf_modules/publish'

params.target_id   = null
params.profile     = 'minimal-silver'
params.container   = 'bronze'
params.bronze_tag  = 'role=bronze'
params.grades      = [
    silver: [tag: 'role=silver', container: 'bronze', prefix: 'silver-skeleton']
]
params.sas_env     = null
params.help        = false

def helpMessage() {
    log.info """
    ================================================================
    Bronze to Silver Skeleton Pipeline
    ================================================================
    Retrieves a dataset from bronze, adds metadata, and lands it in silver.

    Usage:
      nextflow run main.nf --target_id <id> [options]

    Required:
      --target_id ID             ID of the bronze dataset (e.g. 20260723-swift-falcon-8a2b)

    Optional:
      --profile NAME             'minimal-silver' (default) or 'extended-silver'
      -profile NEXTFLOW_PROFILE  'docker' (default)
    ================================================================
    """
}

workflow {
    main:
        if (params.help || !params.target_id) {
            helpMessage()
            exit 0
        }

        sas_ch = MINT_SAS(params.container, params.bronze_tag, 'rl', 168)
        download_input = sas_ch.map { _sas_meta, sas_env -> [params.target_id.trim(), sas_env] }
        
        az_download = AZURE_DOWNLOAD(download_input)

        // Generate silver ID by appending '-silver' to the original ID (for skeleton demo purposes)
        def silver_id = "${params.target_id.trim()}-silver"
        
        payload = az_download.data_dir.map { old_id, path -> 
            [silver_id, path] 
        }
        
        def profile_path = "${projectDir}/profiles/${params.profile}"
        
        def properties = ['sample_id': 'SAM-9999']
        if (params.profile == 'extended-silver') {
            properties['experiment_type'] = 'skeleton_test_type'
        }

        def prov = [
            derived_from: params.target_id.trim(),
            properties: properties
        ]

        PUBLISH(payload, 'silver', profile_path, prov)
}
