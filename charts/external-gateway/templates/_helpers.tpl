{{/* Release-derived base name. */}}
{{- define "eg.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Labels applied to every object (before per-object and commonLabels). */}}
{{- define "eg.stdLabels" -}}
{{- if .Values.standardLabels -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end -}}
{{- end -}}

{{/*
Object metadata. Args: root, name, namespace (optional), labels, annotations, clusterScoped (bool).
Precedence for labels and annotations: per-object, then commonLabels/commonAnnotations, then standard labels.
*/}}
{{- define "eg.meta" -}}
{{- $root := .root -}}
{{- $labels := merge (dict) (default (dict) .labels) (default (dict) $root.Values.commonLabels) (include "eg.stdLabels" $root | fromYaml) -}}
{{- $ann := merge (dict) (default (dict) .annotations) (default (dict) $root.Values.commonAnnotations) -}}
name: {{ .name | quote }}
{{- if not .clusterScoped }}
namespace: {{ default $root.Release.Namespace .namespace | quote }}
{{- end }}
{{- with $labels }}
labels:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $ann }}
annotations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/* DNS-label-safe slug of a hostname, for listener names. */}}
{{- define "eg.slug" -}}
{{- . | lower | replace "*" "wildcard" | replace "." "-" | replace "_" "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* true/false: is this list-item/object enabled (absent key means enabled). */}}
{{- define "eg.isEnabled" -}}
{{- if hasKey . "enabled" -}}{{ if .enabled }}true{{ end }}{{- else -}}true{{- end -}}
{{- end -}}

{{/* Gateway object name. */}}
{{- define "eg.gatewayName" -}}
{{- default (include "eg.fullname" .) .Values.gateway.name -}}
{{- end -}}

{{/* Primary Service name and first port, as YAML. */}}
{{- define "eg.primary" -}}
name: {{ default (include "eg.fullname" .) .Values.service.name | quote }}
{{- with .Values.service.ports }}
port: {{ (first .).port }}
{{- end }}
{{- end -}}

{{/* Secret name written by the primary certificate; empty when the certificate is disabled. */}}
{{- define "eg.certSecretName" -}}
{{- $c := .Values.certificate -}}
{{- if $c.enabled -}}
{{- if $c.secretName -}}
{{- $c.secretName -}}
{{- else if $c.dnsNames -}}
{{- printf "%s-tls" (first $c.dnsNames) -}}
{{- else if .Values.hostnames -}}
{{- printf "%s-tls" (first .Values.hostnames) -}}
{{- else -}}
{{- fail "certificate.enabled needs certificate.secretName, certificate.dnsNames or hostnames" -}}
{{- end -}}
{{- end -}}
{{- end -}}
