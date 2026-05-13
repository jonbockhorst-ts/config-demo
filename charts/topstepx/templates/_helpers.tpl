{{- define "topstepx.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "topstepx.labels" -}}
app.kubernetes.io/name: {{ include "topstepx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "topstepx.renderPostgresConnectionString" -}}
{{- $binding := .binding -}}
Username={{ "{{" }} .{{ .secretPrefix }}Username {{ "}}" }};Password={{ "{{" }} .{{ .secretPrefix }}Password {{ "}}" }};Host={{ "{{" }} .{{ .secretPrefix }}Host {{ "}}" }};Database={{ .database }};Port={{ "{{" }} .{{ .secretPrefix }}Port {{ "}}" }}{{- if $binding.includeErrorDetail }};Include Error Detail=true{{- end }}{{- with $binding.commandTimeout }};Command Timeout={{ . }}{{- end }}
{{- end -}}
