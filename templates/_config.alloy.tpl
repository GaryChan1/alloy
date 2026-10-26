{{/*
The Alloy configuration for the pod-logs collector.

Pipeline:
  discovery.kubernetes  -> pods scheduled on this node
  discovery.relabel     -> filter namespaces, set labels, work out each container's log path
  local.file_match      -> expand the log path globs into files
  loki.source.file      -> tail the files
  loki.process          -> parse the CRI log format, tidy labels
  loki.write            -> push to Loki

Note: the grafana/alloy chart passes this text through `tpl`, so it must not contain "{{".
*/}}
{{- define "alloy-pod-logs.config" -}}
logging {
  level  = "info"
  format = "logfmt"
}

// Pods running on this node. HOSTNAME is set to the node name by the Alloy chart.
discovery.kubernetes "pods" {
  role = "pod"
  selectors {
    role  = "pod"
    field = "spec.nodeName=" + sys.env("HOSTNAME")
  }
{{- with .Values.logs.namespaces }}
  namespaces {
    names = {{ include "alloy-pod-logs.alloyList" . }}
  }
{{- end }}
}

discovery.relabel "pod_logs" {
  targets = discovery.kubernetes.pods.targets
{{- with .Values.logs.excludeNamespaces }}

  rule {
    source_labels = ["__meta_kubernetes_namespace"]
    regex         = {{ join "|" . | quote }}
    action        = "drop"
  }
{{- end }}

  rule {
    source_labels = ["__meta_kubernetes_namespace"]
    target_label  = "namespace"
  }
  rule {
    source_labels = ["__meta_kubernetes_pod_name"]
    target_label  = "pod"
  }
  rule {
    source_labels = ["__meta_kubernetes_pod_container_name"]
    target_label  = "container"
  }
  rule {
    source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_container_name"]
    separator     = "/"
    target_label  = "job"
  }

  // app = the app.kubernetes.io/name label, or failing that the app label.
  rule {
    source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name", "__meta_kubernetes_pod_label_app"]
    separator     = ";"
    regex         = "^;*([^;]+)(;.*)?$"
    target_label  = "app"
  }

  // Log files live at /var/log/pods/<namespace>_<pod>_<uid>/<container>/<restart>.log
  rule {
    source_labels = ["__meta_kubernetes_pod_uid", "__meta_kubernetes_pod_container_name"]
    separator     = "/"
    replacement   = "/var/log/pods/*$1/*.log"
    target_label  = "__path__"
  }
  // Static pods (created by the kubelet, e.g. control-plane components) are keyed by their mirror annotation.
  rule {
    source_labels = ["__meta_kubernetes_pod_annotation_kubernetes_io_config_mirror", "__meta_kubernetes_pod_container_name"]
    separator     = "/"
    regex         = "(.+/.+)"
    replacement   = "/var/log/pods/*$1/*.log"
    target_label  = "__path__"
  }
}

local.file_match "pod_logs" {
  path_targets = discovery.relabel.pod_logs.output
}

loki.source.file "pod_logs" {
  targets       = local.file_match.pod_logs.targets
  tail_from_end = {{ .Values.logs.onlyNewLines }}
  forward_to    = [loki.process.pod_logs.receiver]
}

loki.process "pod_logs" {
  // Kubernetes writes container logs in CRI format: "<time> <stream> <flags> <message>".
  // This strips that prefix, uses the original timestamp, and extracts the stream.
  stage.cri {}

  // stdout or stderr
  stage.labels {
    values = {
      stream = "",
    }
  }

  // loki.source.file adds the file path as a label. It changes with every container restart,
  // so drop it to keep the number of log streams down.
  stage.label_drop {
    values = ["filename"]
  }

  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint {
    url = {{ .Values.loki.url | quote }}
{{- with .Values.loki.tenantId }}
    tenant_id = {{ . | quote }}
{{- end }}
{{- if .Values.loki.basicAuth.enabled }}

    // Read from environment variables, which the pod fills from the credentials Secret.
    basic_auth {
      username = sys.env("LOKI_USERNAME")
      password = sys.env("LOKI_PASSWORD")
    }
{{- end }}
{{- if .Values.loki.insecureSkipVerify }}

    tls_config {
      insecure_skip_verify = true
    }
{{- end }}
  }

  external_labels = {
    cluster = {{ .Values.clusterName | quote }},
  }
}
{{- with .Values.collector.extraConfig }}

// ---- extraConfig ----
{{ . }}
{{- end }}
{{- end }}
