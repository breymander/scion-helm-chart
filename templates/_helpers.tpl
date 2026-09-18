{{/*
Chart name, overridable.
*/}}
{{- define "scion.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name.
*/}}
{{- define "scion.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "scion.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "scion.labels" -}}
helm.sh/chart: {{ include "scion.chart" . }}
{{ include "scion.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: scion
{{- end }}

{{- define "scion.selectorLabels" -}}
app.kubernetes.io/name: {{ include "scion.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "scion.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "scion.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
The directory the hub treats as its state root. pkg/config/hub_config.go puts
the SQLite database at <home>/.scion/hub.db, and the local blob store lives
alongside it, so this is the path that has to be backed by the PVC.
*/}}
{{- define "scion.scionDir" -}}
{{- printf "%s/.scion" (trimSuffix "/" .Values.hub.home) }}
{{- end }}

{{- define "scion.agentNamespace" -}}
{{- default .Release.Namespace .Values.agents.namespace }}
{{- end }}

{{- define "scion.claimName" -}}
{{- default (printf "%s-home" (include "scion.fullname" .)) .Values.persistence.existingClaim }}
{{- end }}

{{- define "scion.settingsSecretName" -}}
{{- default (printf "%s-settings" (include "scion.fullname" .)) .Values.config.existingSecret }}
{{- end }}

{{- define "scion.sessionSecretName" -}}
{{- default (printf "%s-session" (include "scion.fullname" .)) .Values.auth.existingSecret }}
{{- end }}

{{- define "scion.sessionSecretKey" -}}
{{- default "SCION_SERVER_SESSION_SECRET" .Values.auth.existingSecretKey }}
{{- end }}

{{- define "scion.credentialsSecretName" -}}
{{- default (printf "%s-agent-credentials" (include "scion.fullname" .)) .Values.agents.credentials.existingSecret }}
{{- end }}

{{/*
Image reference. A digest wins over a tag; the tag falls back to appVersion.
*/}}
{{- define "scion.image" -}}
{{- $repo := required "image.repository is required. It must be a hub image built WITH web assets embedded - the published ghcr.io/homebrew-scion/scion-hub is built with -tags no_embed_web and its web UI is empty. See the chart README." .Values.image.repository -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" $repo .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" $repo (default .Chart.AppVersion .Values.image.tag) -}}
{{- end -}}
{{- end }}

{{/*
The hub's ingress host. Derived from hub.baseUrl so the two can never drift -
the hub builds its OAuth redirect_uri from baseUrl (pkg/hub/web.go:2043), so a
host that disagrees with it produces a login loop rather than a clear error.
*/}}
{{- define "scion.ingressHost" -}}
{{- $host := .Values.ingress.host -}}
{{- if not $host -}}
{{- $host = (urlParse .Values.hub.baseUrl).host -}}
{{- end -}}
{{- $host = regexReplaceAll ":[0-9]+$" $host "" -}}
{{- if not $host -}}
{{- fail "ingress.enabled is true but no host is available: set ingress.host, or give hub.baseUrl an absolute https:// URL." -}}
{{- end -}}
{{- $host -}}
{{- end }}
