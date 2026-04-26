{{/*
Common helpers for the unifi-os-server chart.
*/}}

{{- define "unifi-os-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "unifi-os-server.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "unifi-os-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "unifi-os-server.labels" -}}
helm.sh/chart: {{ include "unifi-os-server.chart" . }}
{{ include "unifi-os-server.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "unifi-os-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "unifi-os-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "unifi-os-server.image" -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}

{{/* Returns the data PVC name (handles existingClaim). */}}
{{- define "unifi-os-server.dataPVC" -}}
{{- if .Values.persistence.data.existingClaim -}}
{{- .Values.persistence.data.existingClaim -}}
{{- else -}}
{{- printf "%s-data" (include "unifi-os-server.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "unifi-os-server.mongoPVC" -}}
{{- if .Values.persistence.mongo.existingClaim -}}
{{- .Values.persistence.mongo.existingClaim -}}
{{- else -}}
{{- printf "%s-mongo" (include "unifi-os-server.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "unifi-os-server.backupsPVC" -}}
{{- if .Values.persistence.backups.existingClaim -}}
{{- .Values.persistence.backups.existingClaim -}}
{{- else -}}
{{- printf "%s-backups" (include "unifi-os-server.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
TLS secret name. Resolution order:
  1. ingress.tls.secretName (explicit override)
  2. certManager.secretName (explicit override when cert-manager is enabled)
  3. <fullname>-tls (chart default; the Certificate template writes here)
*/}}
{{- define "unifi-os-server.tlsSecretName" -}}
{{- if .Values.ingress.tls.secretName -}}
{{- .Values.ingress.tls.secretName -}}
{{- else if and .Values.certManager.enabled .Values.certManager.secretName -}}
{{- .Values.certManager.secretName -}}
{{- else -}}
{{- printf "%s-tls" (include "unifi-os-server.fullname" .) -}}
{{- end -}}
{{- end -}}
