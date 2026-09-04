{{/* Standard labels applied to every resource this chart creates. */}}
{{- define "bedoux.labels" -}}
app.kubernetes.io/name: bedoux
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/* P13 stages schema-compatible candidate migrations before candidate pods. */}}
{{- define "bedoux.migrationImageReference" -}}
{{- if .Values.canary.enabled -}}
{{- include "bedoux.imageReference" .Values.canary.api.image -}}
{{- else -}}
{{- include "bedoux.imageReference" .Values.api.image -}}
{{- end -}}
{{- end -}}

{{/* One Kubernetes-secret interface for local/in-cluster and P7.1 external RDS. */}}
{{- define "bedoux.databaseCredentialsSecretName" -}}
{{- required "database.credentialsSecret.name is required" .Values.database.credentialsSecret.name -}}
{{- end -}}

{{- define "bedoux.databaseCredentialsSecretKey" -}}
{{- required "database.credentialsSecret.key is required" .Values.database.credentialsSecret.key -}}
{{- end -}}

{{/*
  CI deploys the immutable digest it signed and verified. Local profiles keep the
  existing repository:tag behavior when digest is empty.
*/}}
{{- define "bedoux.imageReference" -}}
{{- if .digest -}}
{{- printf "%s@%s" .repository .digest -}}
{{- else -}}
{{- printf "%s:%s" .repository .tag -}}
{{- end -}}
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

{{/*
  M2 (ADR 0024): one pod spec for the stable api Deployment and the api-canary
  Deployment. They previously existed as two near-identical copies, which is how
  the canary silently lost its topologySpreadConstraints on the HA profile.

  Everything that is genuinely per-side is a parameter; everything else is shared
  by construction, so the two cannot drift again.

    ctx   — root context
    app   — pod label and topology-spread selector ("api" or "api-canary")
    image — the image map to render ( .Values.api.image or .Values.canary.api.image )

  Emitted at column 0. Callers place it with `nindent 6`.
*/}}
{{- define "bedoux.apiPodSpec" -}}
{{- $ctx := .ctx -}}
{{- $api := $ctx.Values.api -}}
serviceAccountName: {{ $api.serviceAccount.name }}
terminationGracePeriodSeconds: {{ $api.termination.gracePeriodSeconds }}
{{- if $api.topologySpread.enabled }}
topologySpreadConstraints:
  - maxSkew: {{ $api.topologySpread.maxSkew }}
    {{- if eq $api.topologySpread.whenUnsatisfiable "DoNotSchedule" }}
    minDomains: {{ $api.topologySpread.minDomains }}
    {{- end }}
    topologyKey: {{ $api.topologySpread.topologyKey | quote }}
    whenUnsatisfiable: {{ $api.topologySpread.whenUnsatisfiable }}
    labelSelector:
      matchLabels:
        app: {{ .app }}
{{- end }}
# Blocks startup until the configured database credential boundary resolves
# and the database accepts the URL consumed by the API.
initContainers:
  - name: wait-for-postgres
    image: {{ include "bedoux.imageReference" .image | quote }}
    command:
      - python
      - -c
      - |
        import time
        from sqlalchemy import create_engine, text
        from app.database_credentials import resolve_database_url
        engine = create_engine(resolve_database_url(), pool_pre_ping=True)
        while True:
            try:
                with engine.connect() as connection:
                    connection.execute(text("SELECT 1"))
                break
            except Exception:
                time.sleep(1)
    env:
      {{- include "bedoux.databaseCredentialEnv" $ctx | nindent 6 }}
containers:
  - name: api
    image: {{ include "bedoux.imageReference" .image | quote }}
    imagePullPolicy: {{ .image.pullPolicy }}
    {{- if gt (int $api.termination.preStopSleepSeconds) 0 }}
    lifecycle:
      preStop:
        exec:
          command:
            - /bin/sh
            - -c
            - {{ printf "sleep %d" (int $api.termination.preStopSleepSeconds) | quote }}
    {{- end }}
    ports:
      - containerPort: 8000
    env:
      {{- include "bedoux.databaseCredentialEnv" $ctx | nindent 6 }}
      # Kill switch (ADR-pending decision #4, docs/IMPLEMENTATION-PLAN.md):
      # off by default in the AWS session values overlay.
      - name: BEDOUX_ORDERS_ENABLED
        value: {{ $api.ordersEnabled | quote }}
      - name: BEDOUX_IMAGE_STORAGE_MODE
        value: {{ $api.imageStorage.mode | quote }}
      - name: BEDOUX_S3_PRESIGN_EXPIRES_SECONDS
        value: {{ $api.imageStorage.presignExpiresSeconds | quote }}
      {{- if eq $api.imageStorage.mode "s3" }}
      - name: BEDOUX_S3_BUCKET
        valueFrom:
          configMapKeyRef:
            name: {{ required "api.imageStorage.s3ConfigMapName is required in s3 mode" $api.imageStorage.s3ConfigMapName }}
            key: {{ $api.imageStorage.s3BucketKey }}
      - name: BEDOUX_S3_REGION
        valueFrom:
          configMapKeyRef:
            name: {{ $api.imageStorage.s3ConfigMapName }}
            key: {{ $api.imageStorage.s3RegionKey }}
      {{- end }}
    resources:
      {{- toYaml $api.resources | nindent 6 }}
    # /health deliberately never touches the database (see apps/api/app/main.py)
    # — DB reachability is guaranteed at startup by the init container above.
    readinessProbe:
      httpGet:
        path: /health
        port: 8000
      initialDelaySeconds: 3
      periodSeconds: 5
      timeoutSeconds: 3
    livenessProbe:
      httpGet:
        path: /health
        port: 8000
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 3
{{- end -}}

{{/*
  M2 (ADR 0024): one pod spec for the stable web Deployment and web-canary.

    ctx       — root context
    app       — pod label and topology-spread selector ("web" or "web-canary")
    image     — .Values.web.image or .Values.canary.web.image
    configMap — the ConfigMap supplying API_UPSTREAM
    command   — optional container command override

  Emitted at column 0. Callers place it with `nindent 6`.
*/}}
{{- define "bedoux.webPodSpec" -}}
{{- $web := .ctx.Values.web -}}
terminationGracePeriodSeconds: {{ $web.termination.gracePeriodSeconds }}
{{- if $web.topologySpread.enabled }}
topologySpreadConstraints:
  - maxSkew: {{ $web.topologySpread.maxSkew }}
    {{- if eq $web.topologySpread.whenUnsatisfiable "DoNotSchedule" }}
    minDomains: {{ $web.topologySpread.minDomains }}
    {{- end }}
    topologyKey: {{ $web.topologySpread.topologyKey | quote }}
    whenUnsatisfiable: {{ $web.topologySpread.whenUnsatisfiable }}
    labelSelector:
      matchLabels:
        app: {{ .app }}
{{- end }}
containers:
  - name: web
    image: {{ include "bedoux.imageReference" .image | quote }}
    imagePullPolicy: {{ .image.pullPolicy }}
    {{- if gt (int $web.termination.preStopSleepSeconds) 0 }}
    lifecycle:
      preStop:
        exec:
          command:
            - /bin/sh
            - -c
            - {{ printf "sleep %d" (int $web.termination.preStopSleepSeconds) | quote }}
    {{- end }}
    {{- with .command }}
    command:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    ports:
      - containerPort: 8080
    envFrom:
      - configMapRef:
          name: {{ .configMap }}
    resources:
      {{- toYaml $web.resources | nindent 6 }}
    readinessProbe:
      httpGet:
        path: /
        port: 8080
      initialDelaySeconds: 3
      periodSeconds: 5
      timeoutSeconds: 3
    livenessProbe:
      httpGet:
        path: /
        port: 8080
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 3
{{- end -}}
