{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "alloy-pod-logs.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels for resources created by this chart.
*/}}
{{- define "alloy-pod-logs.labels" -}}
helm.sh/chart: {{ include "alloy-pod-logs.chart" . }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Name of the pre-delete cleanup hook and its RBAC objects.
*/}}
{{- define "alloy-pod-logs.cleanupName" -}}
{{- printf "%s-cleanup" .Values.collector.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
A list of strings as an Alloy list literal, e.g. ["a", "b"].
*/}}
{{- define "alloy-pod-logs.alloyList" -}}
[{{- range $i, $v := . }}{{ if $i }}, {{ end }}{{ $v | quote }}{{- end }}]
{{- end }}
