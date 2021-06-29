version 1.0

import "GATKSVPipelineClinical.wdl" as module
import "TestUtils.wdl" as utils

workflow GATKSVPipelineClinicalTest {
  input {
    String test_name
    String case_sample
    Array[String] ref_samples
    String base_metrics
  }

  call module.GATKSVPipelineClinical {
    input:
      sample_id = case_sample,
      ref_samples = ref_samples
  }

  Array[String] samples = flatten([[case_sample], ref_samples])

  call utils.PlotMetrics {
    input:
      name = test_name,
      samples = samples,
      test_metrics = GATKSVPipelineClinical.metrics_file,
      base_metrics = base_metrics
  }

  output {
    File metrics = GATKSVPipelineClinical.metrics_file
    File metrics_plot_pdf = PlotMetrics.metrics_plot_pdf
    File metrics_plot_tsv = PlotMetrics.metrics_plot_tsv
  }
  
  meta {
    author: "Guest author"
    email: "guest@gmail.com"
  }
}
