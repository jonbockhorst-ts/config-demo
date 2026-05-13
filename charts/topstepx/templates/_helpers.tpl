{{- define "topstepx.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "topstepx.labels" -}}
app.kubernetes.io/name: {{ include "topstepx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "topstepx.renderValueTpl" -}}
{{- tpl (required .message .value) .context -}}
{{- end -}}
