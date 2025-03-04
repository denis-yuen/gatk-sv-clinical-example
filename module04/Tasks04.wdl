version 1.0

import "Structs.wdl"

task SplitVariants {
  input {
    File vcf
    Int n_per_split
    Boolean generate_bca
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
    Array[File] lt5kb_beds = glob("lt5kb.*")
    Array[File] gt5kb_beds = glob("gt5kb.*")
    Array[File] bca_beds = glob("bca.*")
  }
  command <<<

    set -euo pipefail
    svtk vcf2bed ~{vcf} stdout \
      | awk -v OFS="\t" '(($5=="DEL" || $5=="DUP") && $3-$2>=5000) {print $1, $2, $3, $4, $6, $5}' \
      | split -l ~{n_per_split} -a 6 - gt5kb.
    svtk vcf2bed ~{vcf} stdout \
      | awk -v OFS="\t" '(($5=="DEL" || $5=="DUP") && $3-$2<5000) {print $1, $2, $3, $4, $6, $5}' \
      | split -l ~{n_per_split} -a 6 - lt5kb.
    if [ ~{generate_bca} == "true" ]; then
      svtk vcf2bed ~{vcf} stdout \
        | awk -v OFS="\t" '($5!="DEL" && $5!="DUP") {print $1, $2, $3, $4, $6, $5}' \
        | split -l ~{n_per_split} -a 6 - bca.
    fi

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

task SplitVcf {
  input {
    File vcf
    Int n_per_split
    String evidence_type    # pe or sr
    Boolean bgzip           # bgzip output (for SR)
    String sv_mini_docker
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

  String output_ext = if bgzip then "vcf.gz" else "vcf"

  output {
    Array[File] vcfs = glob("~{evidence_type}.*.~{output_ext}")
  }
  command <<<

    set -euxo pipefail
    if [[ ~{vcf} == *.gz ]] ; then
      zcat ~{vcf} | sed -n -e '/^#/p' > header.vcf;
      zcat ~{vcf} | sed -e '/^#/d' | split -l ~{n_per_split} - ~{evidence_type}.;
    else
      sed -n -e '/^#/p' ~{vcf} > header.vcf;
      sed -e '/^#/d' ~{vcf} | split -l ~{n_per_split} - ~{evidence_type}.;
    fi
    for f in ~{evidence_type}.*; do cat header.vcf $f ~{if bgzip then "| bgzip -c > $f.vcf.gz" else "> $f.vcf"}; done
  
  >>>
  runtime {
    cpu: select_first([runtime_attr.cpu_cores, default_attr.cpu_cores])
    memory: select_first([runtime_attr.mem_gb, default_attr.mem_gb]) + " GiB"
    disks: "local-disk " + select_first([runtime_attr.disk_gb, default_attr.disk_gb]) + " HDD"
    bootDiskSizeGb: select_first([runtime_attr.boot_disk_gb, default_attr.boot_disk_gb])
    docker: sv_mini_docker
    preemptible: select_first([runtime_attr.preemptible_tries, default_attr.preemptible_tries])
    maxRetries: select_first([runtime_attr.max_retries, default_attr.max_retries])
  }
}

task AddGenotypes {
  input {
    File vcf
    File genotypes
    File varGQ
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
    File genotyped_vcf = "${prefix}.genotyped.vcf.gz"
  }
  command <<<

    set -euo pipefail

    # in some cases a vargq cannot be computed and is returned as '.'. Remove these from the final vcf.
    gzip -cd ~{varGQ} | awk '$5 == "." {print $1}' > bad.vargq.list
    gzip -cd ~{vcf} | grep -wvf bad.vargq.list | bgzip -c > clean.vcf.gz
    gzip -cd ~{genotypes} | grep -wvf bad.vargq.list | bgzip -c > clean.genotypes.txt.gz
    gzip -cd ~{varGQ} | grep -wvf bad.vargq.list | bgzip -c > clean.vargq.txt.gz

    /opt/sv-pipeline/04_variant_resolution/scripts/add_genotypes.py \
      clean.vcf.gz \
      clean.genotypes.txt.gz \
      clean.vargq.txt.gz \
      ~{prefix}.genotyped.vcf;
    vcf-sort -c ~{prefix}.genotyped.vcf | bgzip -c > ~{prefix}.genotyped.vcf.gz
  
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

task MakeSubsetVcf {
  input {
    File vcf
    File bed
    String sv_mini_docker
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

  String prefix = basename(bed, ".bed")

  output {
    File subset_vcf = "${prefix}.vcf.gz"
  }
  command <<<

    set -euo pipefail
    zcat ~{vcf} | fgrep -e "#" > ~{prefix}.vcf;
    zcat ~{vcf} | fgrep -w -f <(cut -f4 ~{bed}) >> ~{prefix}.vcf;
    bgzip ~{prefix}.vcf
  
  >>>
  runtime {
    cpu: select_first([runtime_attr.cpu_cores, default_attr.cpu_cores])
    memory: select_first([runtime_attr.mem_gb, default_attr.mem_gb]) + " GiB"
    disks: "local-disk " + select_first([runtime_attr.disk_gb, default_attr.disk_gb]) + " HDD"
    bootDiskSizeGb: select_first([runtime_attr.boot_disk_gb, default_attr.boot_disk_gb])
    docker: sv_mini_docker
    preemptible: select_first([runtime_attr.preemptible_tries, default_attr.preemptible_tries])
    maxRetries: select_first([runtime_attr.max_retries, default_attr.max_retries])
  }
}

task ConcatGenotypedVcfs {
  input {
    Array[File] lt5kb_vcfs
    Array[File] gt5kb_vcfs
    Array[File] bca_vcfs
    String batch
    String evidence_type    # depth or pesr
    String sv_mini_docker
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
    File genotyped_vcf = "${batch}.~{evidence_type}.vcf.gz"
    File genotyped_vcf_index = "${batch}.~{evidence_type}.vcf.gz.tbi"
  }
  command <<<

    set -euo pipefail
    vcf-concat ~{sep=" " lt5kb_vcfs} ~{sep=" " gt5kb_vcfs} ~{sep=" " bca_vcfs} \
      | vcf-sort -c \
      | bgzip -c > ~{batch}.~{evidence_type}.vcf.gz
    tabix -p vcf ~{batch}.~{evidence_type}.vcf.gz
  
  >>>
  runtime {
    cpu: select_first([runtime_attr.cpu_cores, default_attr.cpu_cores])
    memory: select_first([runtime_attr.mem_gb, default_attr.mem_gb]) + " GiB"
    disks: "local-disk " + select_first([runtime_attr.disk_gb, default_attr.disk_gb]) + " HDD"
    bootDiskSizeGb: select_first([runtime_attr.boot_disk_gb, default_attr.boot_disk_gb])
    docker: sv_mini_docker
    preemptible: select_first([runtime_attr.preemptible_tries, default_attr.preemptible_tries])
    maxRetries: select_first([runtime_attr.max_retries, default_attr.max_retries])
  }
}

task MergePESRCounts {
  input {
    Array[File]+ count_list
    Array[File] sum_list
    String evidence_type    # pe or sr
    String sv_mini_docker
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
    File counts = "~{evidence_type}_counts.txt.gz"
    File sum = "~{evidence_type}_sum.txt.gz"
  }
  command <<<

    set -euo pipefail
    zcat ~{sep=" " count_list} | fgrep -v -e "name" | gzip -c > ~{evidence_type}_counts.txt.gz
    echo "" | gzip -c > empty_file.gz
    cat ~{sep=" " sum_list} empty_file.gz > ~{evidence_type}_sum.txt.gz
  
  >>>
  runtime {
    cpu: select_first([runtime_attr.cpu_cores, default_attr.cpu_cores])
    memory: select_first([runtime_attr.mem_gb, default_attr.mem_gb]) + " GiB"
    disks: "local-disk " + select_first([runtime_attr.disk_gb, default_attr.disk_gb]) + " HDD"
    bootDiskSizeGb: select_first([runtime_attr.boot_disk_gb, default_attr.boot_disk_gb])
    docker: sv_mini_docker
    preemptible: select_first([runtime_attr.preemptible_tries, default_attr.preemptible_tries])
    maxRetries: select_first([runtime_attr.max_retries, default_attr.max_retries])
  }
}

task RDTestGenotype {
  input {
    File bed
    File coveragefile
    File medianfile
    File famfile
    Array[String] samples
    File gt_cutoffs
    Int n_bins
    String prefix
    Boolean generate_melted_genotypes
    String sv_pipeline_rdtest_docker
    RuntimeAttr? runtime_attr_override
  }

  parameter_meta {
    coveragefile: {
      localization_optional: true
    }
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
    File genotypes = "${prefix}.geno"
    File copy_states = "${prefix}.median_geno"
    File metrics = "${prefix}.metrics"
    File gq = "${prefix}.gq"
    File varGQ = "${prefix}.vargq"
    File melted_genotypes = "rd.geno.cnv.bed.gz"
  }
  command <<<

    set -euo pipefail
    /opt/RdTest/localize_bincov.sh ~{bed} ~{coveragefile}
    Rscript /opt/RdTest/RdTest.R \
      -b ~{bed} \
      -c local_coverage.bed.gz \
      -m ~{medianfile} \
      -f ~{famfile} \
      -n ~{prefix} \
      -w ~{write_lines(samples)} \
      -i ~{n_bins} \
      -r ~{gt_cutoffs} \
      -y /opt/RdTest/bin_exclude.bed.gz \
      -g TRUE;
    if [ ~{generate_melted_genotypes} == "true" ]; then
      /opt/sv-pipeline/04_variant_resolution/scripts/merge_RdTest_genotypes.py ~{prefix}.geno ~{prefix}.gq rd.geno.cnv.bed;
      sort -k1,1V -k2,2n rd.geno.cnv.bed | uniq | bgzip -c > rd.geno.cnv.bed.gz
    else
      echo "" | bgzip -c > rd.geno.cnv.bed.gz
    fi
  
  >>>
  runtime {
    cpu: select_first([runtime_attr.cpu_cores, default_attr.cpu_cores])
    memory: select_first([runtime_attr.mem_gb, default_attr.mem_gb]) + " GiB"
    disks: "local-disk " + select_first([runtime_attr.disk_gb, default_attr.disk_gb]) + " HDD"
    bootDiskSizeGb: select_first([runtime_attr.boot_disk_gb, default_attr.boot_disk_gb])
    docker: sv_pipeline_rdtest_docker
    preemptible: select_first([runtime_attr.preemptible_tries, default_attr.preemptible_tries])
    maxRetries: select_first([runtime_attr.max_retries, default_attr.max_retries])
  }
}


task CountPE {
  input {
    File vcf
    File discfile
    File medianfile
    Array[String] samples
    String sv_pipeline_docker
    RuntimeAttr? runtime_attr_override
  }

  parameter_meta {
    discfile: {
      localization_optional: true
    }
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
  
  String prefix = basename(vcf, ".vcf")

  output {
    File pe_counts = "${prefix}.pe_counts.txt.gz"
  }
  command <<<

    set -euo pipefail
    svtk vcf2bed --split-bnd --no-header ~{vcf} test.bed
    awk -v OFS="\t" -v window=5000 '{if ($2-window>0){print $1,$2-window,$2+window}else{print $1,0,$2+window}}' test.bed  >> region.bed
    awk -v OFS="\t" -v window=5000 '{if ($3-window>0){print $1,$3-window,$3+window}else{print $1,0,$3+window}}' test.bed  >> region.bed
    sort -k1,1 -k2,2n region.bed > region.sorted.bed
    bedtools merge -i region.sorted.bed > region.merged.bed
    GCS_OAUTH_TOKEN=`gcloud auth application-default print-access-token` \
      tabix -R region.merged.bed ~{discfile} | bgzip -c > PE.txt.gz
    tabix -b 2 -e 2 PE.txt.gz
    svtk count-pe --index PE.txt.gz.tbi -s ~{write_lines(samples)} --medianfile ~{medianfile} ~{vcf} PE.txt.gz ~{prefix}.pe_counts.txt
    gzip ~{prefix}.pe_counts.txt
  
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

task CountSR {
  input {
    File vcf
    File splitfile
    File medianfile
    Array[String] samples
    String sv_pipeline_docker
    RuntimeAttr? runtime_attr_override
  }

  parameter_meta {
    splitfile: {
      localization_optional: true
    }
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
  
  String prefix = basename(vcf, ".vcf")

  output {
    File sr_counts = "${prefix}.sr_counts.txt.gz"
    File sr_sum = "${prefix}.sr_sum.txt.gz"
  }
  command <<<

    set -euo pipefail
    svtk vcf2bed --split-bnd --no-header ~{vcf} test.bed
    awk -v OFS="\t" '{if ($2-250>0){print $1,$2-250,$2+250}else{print $1,0,$2+250}}' test.bed  >> region.bed
    awk -v OFS="\t" '{if ($3-250>0){print $1,$3-250,$3+250}else{print $1,0,$3+250}}' test.bed  >> region.bed
    sort -k1,1 -k2,2n region.bed > region.sorted.bed
    bedtools merge -i region.sorted.bed > region.merged.bed
    GCS_OAUTH_TOKEN=`gcloud auth application-default print-access-token` \
      tabix -R region.merged.bed ~{splitfile} | bgzip -c > SR.txt.gz
    tabix -b 2 -e 2 SR.txt.gz
    svtk count-sr --index SR.txt.gz.tbi -s ~{write_lines(samples)} --medianfile ~{medianfile} ~{vcf} SR.txt.gz ~{prefix}.sr_counts.txt
    /opt/sv-pipeline/04_variant_resolution/scripts/sum_SR.sh ~{prefix}.sr_counts.txt ~{prefix}.sr_sum.txt.gz
    gzip ~{prefix}.sr_counts.txt
  
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
