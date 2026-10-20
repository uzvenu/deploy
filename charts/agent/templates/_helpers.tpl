{{/* Merge whole EnvVar entries by name: later lists win, including valueFrom. */}}
{{- define "agent.mergeEnv" -}}
{{- $env := dict -}}
{{- range . -}}
{{- range . -}}
{{- $_ := set $env .name . -}}
{{- end -}}
{{- end -}}
{{- range $name := keys $env | sortAlpha -}}
{{- toYaml (list (get $env $name)) }}
{{ end -}}
{{- end -}}
