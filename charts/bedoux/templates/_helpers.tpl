{{/* Standard labels applied to every resource this chart creates. */}}
{{- define "bedoux.labels" -}}
app.kubernetes.io/name: bedoux
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/* One secret interface for both in-cluster Postgres and P7 external RDS. */}}
{{- define "bedoux.databaseCredentialsSecretName" -}}
{{- required "database.credentialsSecret.name is required" .Values.database.credentialsSecret.name -}}
{{- end -}}

{{- define "bedoux.databaseCredentialsSecretKey" -}}
{{- required "database.credentialsSecret.key is required" .Values.database.credentialsSecret.key -}}
{{- end -}}
