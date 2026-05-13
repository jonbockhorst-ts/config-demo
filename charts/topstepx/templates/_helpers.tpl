{{- define "topstepx.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "topstepx.labels" -}}
app.kubernetes.io/name: {{ include "topstepx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "topstepx.lowerFirst" -}}
{{- $value := . -}}
{{- if eq (len $value) 0 -}}
{{- "" -}}
{{- else -}}
{{- printf "%s%s" (lower (substr 0 1 $value)) (substr 1 (len $value) $value) -}}
{{- end -}}
{{- end -}}

{{- define "topstepx.esoVar" -}}
{{- printf "{{ .%s }}" . -}}
{{- end -}}

{{- define "topstepx.cleanSegment" -}}
{{- regexReplaceAll "[^A-Za-z0-9]+" . "" -}}
{{- end -}}

{{- define "topstepx.pathToken" -}}
{{- $parts := . -}}
{{- $token := "" -}}
{{- range $index, $part := $parts -}}
  {{- $clean := include "topstepx.cleanSegment" $part -}}
  {{- if eq $index 0 -}}
    {{- $token = printf "%s%s" $token (include "topstepx.lowerFirst" $clean) -}}
  {{- else -}}
    {{- $token = printf "%s%s" $token $clean -}}
  {{- end -}}
{{- end -}}
{{- $token -}}
{{- end -}}

{{- define "topstepx.pathString" -}}
{{- join "." . -}}
{{- end -}}

{{- define "topstepx.secretNodeIsLeaf" -}}
{{- $node := . -}}
{{- if not (kindIs "map" $node) -}}
false
{{- else -}}
  {{- $contentKeys := omit $node "remoteKey" | keys -}}
  {{- if and (hasKey $node "property") (eq (len $contentKeys) 1) -}}
true
  {{- else -}}
false
  {{- end -}}
{{- end -}}
{{- end -}}

{{- define "topstepx.renderSecretJsonMembers" -}}
{{- $node := .node -}}
{{- $path := .path -}}
{{- $entries := omit $node "remoteKey" -}}
{{- $keys := keys $entries | sortAlpha -}}
{{- range $index, $key := $keys }}
{{- $child := get $entries $key -}}
{{- $childPath := concat $path (list $key) -}}
{{- if eq (include "topstepx.secretNodeIsLeaf" $child) "true" -}}
"{{ $key }}": "{{ include "topstepx.esoVar" (include "topstepx.pathToken" $childPath) }}"
{{- else -}}
"{{ $key }}": {
{{ include "topstepx.renderSecretJsonMembers" (dict "node" $child "path" $childPath) | nindent 2 }}
}
{{- end -}}{{- if lt $index (sub (len $keys) 1) }},{{ end }}
{{- end -}}
{{- end -}}

{{- define "topstepx.renderSecretDataEntries" -}}
{{- $node := .node -}}
{{- $path := .path -}}
{{- $inheritedRemoteKey := .remoteKey -}}
{{- $nodeRemoteKey := default $inheritedRemoteKey (get $node "remoteKey") -}}
{{- $entries := omit $node "remoteKey" -}}
{{- range $key := keys $entries | sortAlpha }}
{{- $child := get $entries $key -}}
{{- $childPath := concat $path (list $key) -}}
{{- if eq (include "topstepx.secretNodeIsLeaf" $child) "true" }}
    - secretKey: {{ include "topstepx.pathToken" $childPath }}
      remoteRef:
        key: {{ required (printf "secrets.%s.remoteKey is required" (include "topstepx.pathString" $childPath)) (default $nodeRemoteKey (get $child "remoteKey")) | quote }}
        property: {{ default (include "topstepx.lowerFirst" $key) (get $child "property") }}
{{- else }}
{{ include "topstepx.renderSecretDataEntries" (dict "node" $child "path" $childPath "remoteKey" $nodeRemoteKey) }}
{{- end }}
{{- end -}}
{{- end -}}
