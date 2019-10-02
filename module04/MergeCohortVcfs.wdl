##########################################################################################

## Base script:   https://portal.firecloud.org/#methods/Talkowski-SV/04_v2_make_cohort_VCFs/3/wdl

## Github commit: talkowski-lab/gatk-sv-v1:<ENTER HASH HERE IN FIRECLOUD>

##########################################################################################

version 1.0

import "../Structs.wdl"

workflow MergeCohortVcfs {
  input {
    Array[File] depth_vcfs    # Filtered depth VCFs across batches
    Array[File] pesr_vcfs     # Filtered PESR VCFs across batches
    String sv_pipeline_docker
    RuntimeAttr? runtime_attr_merge_pesr
    RuntimeAttr? runtime_attr_merge_depth
  }

  call MergeVcfs as MergePESRVcfs {
    input:
      vcfs = pesr_vcfs,
      prefix = "all_batches.pesr",
      sv_pipeline_docker = sv_pipeline_docker,
      runtime_attr_override = runtime_attr_merge_pesr
  }

  call MergeVcfs as MergeDepthVcfs {
    input:
      vcfs = depth_vcfs,
      prefix = "all_batches.depth",
      sv_pipeline_docker = sv_pipeline_docker,
      runtime_attr_override = runtime_attr_merge_depth
  }

  output {
    File cohort_pesr_vcf = MergePESRVcfs.merged_vcf
    File cohort_depth_vcf = MergeDepthVcfs.merged_vcf
  }
}

task MergeVcfs {
  input {
    Array[File] vcfs
    String prefix
    String sv_pipeline_docker
    RuntimeAttr? runtime_attr_override
  }

  RuntimeAttr default_attr = object {
    cpu_cores: 1, 
    mem_gb: 3.75, 
    disk_gb: 10,
    boot_disk_gb: 10,
    preemptible_tries: 3,
    max_retries: 1
  }
  RuntimeAttr runtime_attr = select_first([runtime_attr_override, default_attr])

  output {
    File merged_vcf = "${prefix}.vcf.gz"
  }
  command <<<

    set -euo pipefail
    /opt/sv-pipeline/04_variant_resolution/scripts/MergeVcfs.py ~{write_lines(vcfs)} ~{prefix}.vcf
    vcf-sort -c ~{prefix}.vcf | bgzip -c > ~{prefix}.vcf.gz
  
  >>>
  runtime {
    cpu: select_first([runtime_attr.cpu_cores, default_attr.cpu_cores])
    memory: select_first([runtime_attr.mem_gb, default_attr.mem_gb]) + " GiB"
    disks: "local-disk " + select_first([runtime_attr.disk_gb, default_attr.disk_gb]) + " HDD"
    bootDiskSizeGb: select_first([runtime_attr.boot_disk_gb, default_attr.boot_disk_gb])
    docker: sv_pipeline_docker
    preemptible: select_first([runtime_attr.preemptible_tries, default_attr.preemptible_tries])
    maxRetries: select_first([runtime_attr.max_retries, default_attr.max_retries])
  }
}
