{{/* Standard labels applied to every resource this chart creates. */}}
{{- define "bedoux.labels" -}}
app.kubernetes.io/name: bedoux
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/* One Kubernetes-secret interface for local/in-cluster and P7.1 external RDS. */}}
{{- define "bedoux.databaseCredentialsSecretName" -}}
{{- required "database.credentialsSecret.name is required" .Values.database.credentialsSecret.name -}}
{{- end -}}

{{- define "bedoux.databaseCredentialsSecretKey" -}}
{{- required "database.credentialsSecret.key is required" .Values.database.credentialsSecret.key -}}
{{- end -}}

{{/*
  The application, migration Job, and seed Job all consume the same boundary.
  In Secrets Manager mode only the non-secret name and region enter the Pod;
  the SDK fetches the JSON DATABASE_URL using the Pod ServiceAccount identity.
*/}}
{{- define "bedoux.databaseCredentialEnv" -}}
{{- if eq .Values.database.credentialSource "secrets-manager" }}
- name: BEDOUX_DATABASE_SECRET_NAME
  value: {{ required "database.secretManager.name is required in secrets-manager mode" .Values.database.secretManager.name | quote }}
- name: BEDOUX_DATABASE_SECRET_REGION
  value: {{ required "database.secretManager.region is required in secrets-manager mode" .Values.database.secretManager.region | quote }}
{{- else if eq .Values.database.credentialSource "kubernetes-secret" }}
- name: BEDOUX_DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ include "bedoux.databaseCredentialsSecretName" . }}
      key: {{ include "bedoux.databaseCredentialsSecretKey" . }}
{{- else }}
{{- fail "database.credentialSource must be kubernetes-secret or secrets-manager" }}
{{- end }}
{{- end -}}
