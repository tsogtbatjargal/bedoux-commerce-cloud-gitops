{{/* Standard labels applied to every resource this chart creates. */}}
{{- define "bedoux.labels" -}}
app.kubernetes.io/name: bedoux
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}
