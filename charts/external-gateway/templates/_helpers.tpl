{{/* Release-derived base name. */}}
{{- define "eg.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Labels applied to every object (before per-object and commonLabels). */}}
{{- define "eg.stdLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{/*
Object metadata. Args: root, name, labels, annotations.
Precedence for labels and annotations: per-object, then commonLabels/commonAnnotations, then standard labels.
*/}}
{{- define "eg.meta" -}}
{{- $root := .root -}}
{{- $labels := merge (dict) (default (dict) .labels) (default (dict) $root.Values.commonLabels) (include "eg.stdLabels" $root | fromYaml) -}}
{{- $ann := merge (dict) (default (dict) .annotations) (default (dict) $root.Values.commonAnnotations) -}}
name: {{ .name | quote }}
namespace: {{ $root.Release.Namespace | quote }}
labels:
  {{- toYaml $labels | nindent 2 }}
{{- with $ann }}
annotations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/* DNS-label-safe slug of a hostname, for listener names. */}}
{{- define "eg.slug" -}}
{{- . | lower | replace "*" "wildcard" | replace "." "-" | replace "_" "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Gateway object name. */}}
{{- define "eg.gatewayName" -}}
{{- default (include "eg.fullname" .) .Values.gateway.name -}}
{{- end -}}

{{/* Name of the Service at index $i in .Values.services. The first defaults to the release name. */}}
{{- define "eg.serviceName" -}}
{{- if .svc.name -}}
{{- .svc.name -}}
{{- else if eq (int .index) 0 -}}
{{- include "eg.fullname" .root -}}
{{- else -}}
{{- fail "every service after the first needs a name" -}}
{{- end -}}
{{- end -}}
