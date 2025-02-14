{{/*
Expand the name of the chart.
*/}}
{{- define "chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "chart.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "chart.labels" -}}
helm.sh/chart: {{ include "chart.chart" . }}
{{ include "chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Insert config values if defined (including arrays)
*/}}
{{- define "chart.config.values" -}}
  {{- if .config }}
    {{- range $key, $value := .config }}
    {{ $type := (printf "%T" $value) }}
    {{- if eq $type "[]interface {}" }}
  {{ $key }}: {{ $value | toYaml | nindent 2 }}
    {{- end }}
    {{ if eq $type "string" }}
  {{ $key }}: {{ $value | quote }}
    {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{/*
Get docker image for deployment
*/}}
{{- define "chart.deployment.docker-image" -}}
  {{- $dockerRegistry := .context.Values.dockerRegistry }}
  {{- $dockerImage := .appName }}
  {{- $dockerTag := default "latest" .context.Values.dockerTag }}
  {{- if .deployment.image }}
    {{- if .deployment.image.registry }}
      {{- $dockerRegistry = .deployment.image.registry }}
    {{- end }}
    {{- if .deployment.image.name }}
      {{- $dockerImage = .deployment.image.name }}
    {{- end }}
    {{- if .deployment.image.tag }}
      {{- $dockerTag = .deployment.image.tag }}
    {{- end }}
  {{- end }}
  {{- printf "%s/%s:%s" $dockerRegistry $dockerImage $dockerTag }}
{{- end }}

{{/*
Add env to deployment
*/}}
{{- define "chart.deployment.env" -}}
  {{- $addEnv := 0 }}
  {{- $addContainerEnv := 0 }}
  {{- if .deployment.env }}
    {{- if gt (len .deployment.env) 0 }}
      {{- $addEnv = 1 }}
    {{- end }}
  {{- end }}
  {{- if .deployment.container }}
    {{- if .deployment.container.env }}
      {{- if gt (len .deployment.container.env) 0 }}
        {{- $addContainerEnv = 1 }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if or (eq $addEnv 1) (eq $addContainerEnv 1) }}
env:
    {{- if eq $addEnv 1 }}
      {{- range $key, $value := .deployment.env }}
  - name: {{ $key }}
    value: {{ $value | quote }}
      {{- end }}
    {{- end }}
    {{- if eq $addContainerEnv 1 }}
      {{- $env := toYaml .deployment.container.env }}
      {{- $env = regexReplaceAll "\\${chart\\[([^\\]]+)\\]}" $env (printf "%s-$1" (include "chart.fullname" $.context) ) }}
      {{- $env | nindent 2 }}
    {{- end }}
  {{- end }}
{{- end }}

{{/*
Add env to deployment
*/}}
{{- define "chart.deployment.envFrom" -}}
  {{- $addEnvFrom := 0 }}
  {{- $addEnvFromConfig := 0 }}
  {{- $addContainerEnvFrom := 0 }}
  {{- $addEnvFromVault := 0 }}
  {{- if .deployment.envFrom }}
    {{- if gt (len .deployment.envFrom) 0 }}
      {{- $addEnvFrom = 1 }}
    {{- end }}
  {{- end }}
  {{- if .deployment.config }}
    {{- if gt (len .deployment.config) 0 }}
      {{- $addEnvFromConfig = 1 }}
    {{- end }}
  {{- end }}
  {{- if .deployment.container }}
    {{- if .deployment.container.envFrom }}
      {{- if gt (len .deployment.container.envFrom) 0 }}
        {{- $addContainerEnvFrom = 1 }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if .context.Values.vault.enabled }}
    {{- if .deployment.vault }}
      {{- if .deployment.vault.secretConfig }}
        {{- $addEnvFromVault = 1 }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if or (eq $addEnvFrom 1) (eq $addEnvFromConfig 1) (eq $addContainerEnvFrom 1) (eq $addEnvFromVault 1) }}
envFrom:
    {{/* Add from envFrom */}}
    {{- if eq $addEnvFrom 1 }}
      {{- range $item := .deployment.envFrom }}
        {{- range $key, $value := $item }}
  - {{ $key }}:
      name: {{ regexReplaceAll "\\${chart\\[([^\\]]+)\\]}" $value (printf "%s-$1" (include "chart.fullname" $.context) ) }}
        {{- end }}
      {{- end }}
    {{- end }}
    {{/* Add from config */}}
    {{- if eq $addEnvFromConfig 1 }}
  - configMapRef:
      name: {{ include "chart.fullname" .context }}-{{ .appName }}
    {{- end }}
    {{/* Add from container.envFrom */}}
    {{- if eq $addContainerEnvFrom 1 }}
      {{- $envFrom := toYaml .deployment.container.envFrom }}
      {{- $envFrom = regexReplaceAll "\\${chart\\[([^\\]]+)\\]}" $envFrom (printf "%s-$1" (include "chart.fullname" $.context) ) }}
      {{- $envFrom | nindent 2 }}
    {{- end }}
    {{/* Add from vault */}}
    {{- if eq $addEnvFromVault 1 }}
      {{- $secretName := printf "%s-%s" (include "chart.fullname" .context) .appName }}
      {{- if .deployment.vault.secretName }}
        {{- $secretName = .deployment.vault.secretName }}
      {{- end }}
  - secretRef:
      name: {{ $secretName }}
    {{- end }}
  {{- end }}
{{- end }}

{{/*
Add realoder annotation to deployment
*/}}
{{- define "chart.deployment.reloader-annotation" -}}
  {{- $configs := list }}
  {{- if .deployment.config }}
    {{- if gt (len .deployment.config) 0 }}
      {{- $configs = append $configs ( printf "%s-%s" (include "chart.fullname" .context) .appName) }}
    {{- end }}
  {{- end }}
  {{- if .deployment.envFrom }}
    {{- range $item := .deployment.envFrom }}
      {{- range $key, $value := $item }}
        {{- if eq $key "configMapRef" }}
          {{- $configs = append $configs (regexReplaceAll "\\${chart\\[([^\\]]+)\\]}" $value (printf "%s-$1" (include "chart.fullname" $.context) )) }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if .deployment.container }}
    {{- if .deployment.container.envFrom }}
      {{- range $item := .deployment.container.envFrom }}
        {{- range $key, $value := $item }}
          {{- if eq $key "configMapRef" }}
            {{- $configs = append $configs (regexReplaceAll "\\${chart\\[([^\\]]+)\\]}" $value.name (printf "%s-$1" (include "chart.fullname" $.context) )) }}
          {{- end }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if gt (len $configs) 0 }}
    {{- $configAnnotation := "" }}
    {{- range $config := $configs }}
      {{- $configAnnotation = printf "%s%s," $configAnnotation $config }}
    {{- end }}
    {{- $configAnnotation = trimSuffix "," $configAnnotation }}
configmap.reloader.stakater.com/reload: {{ $configAnnotation | quote }}
  {{- end }}

  {{- $secrets := list }}
  {{- if .deployment.envFrom }}
    {{- range $item := .deployment.envFrom }}
      {{- range $key, $value := $item }}
        {{- if eq $key "secretRef" }}
          {{- $secrets = append $secrets (regexReplaceAll "\\${chart\\[([^\\]]+)\\]}" $value (printf "%s-$1" (include "chart.fullname" $.context) )) }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if .deployment.container }}
    {{- if .deployment.container.envFrom }}
      {{- range $item := .deployment.container.envFrom }}
        {{- range $key, $value := $item }}
          {{- if eq $key "secretRef" }}
            {{- $secrets = append $secrets (regexReplaceAll "\\${chart\\[([^\\]]+)\\]}" $value.name (printf "%s-$1" (include "chart.fullname" $.context) )) }}
          {{- end }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if .context.Values.vault.enabled }}
    {{- if .deployment.enabled }}
      {{- if .deployment.vault }}
        {{- if .deployment.vault.secretConfig }}
          {{- $secretName := printf "%s-%s" (include "chart.fullname" .context) .appName }}
          {{- if .deployment.vault.secretName }}
            {{- $secretName = .deployment.vault.secretName }}
          {{- end }}
          {{- $secrets = append $secrets $secretName }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if gt (len $secrets) 0 }}
    {{- $secretAnnotation := "" }}
    {{- range $secret := $secrets }}
      {{- $secretAnnotation = printf "%s%s," $secretAnnotation $secret }}
    {{- end }}
    {{- $secretAnnotation = trimSuffix "," $secretAnnotation }}
secret.reloader.stakater.com/reload: {{ $secretAnnotation | quote }}
  {{- end }}
{{- end }}

{{/*
Generate external secrets for a deployment
*/}}
{{- define "chart.external-secrets.generate" -}}
{{- if .context.Values.vault.enabled }}
  {{- $vaultKeysMap := dict }}
  {{- if .config.secretConfig }}
    {{- range $key, $value := .config.secretConfig }}
      {{- $vaultKeysMap = set $vaultKeysMap $key true }}
    {{- end }}
  {{- end }}
  {{- if .config.templateSecretConfig }}
    {{- $templateContent := toYaml .config.templateSecretConfig }}
    {{- range $key := regexFindAll "{{@([^:]+):([^}]+)}}" $templateContent -1 }}
      {{- $key = regexReplaceAll "{{@([^:]+):([^}]+)}}" $key "${1}" }}
      {{- $vaultKeysMap = set $vaultKeysMap $key true }}
    {{- end }}
  {{- end }}

  {{- $vaultKeys := list }}
  {{- range $key, $value := $vaultKeysMap }}
    {{- $vaultKeys = append $vaultKeys $key }}
  {{- end }}

  {{- if ne (len $vaultKeys) 0 }}
    {{- $secretName := printf "%s-%s" (include "chart.fullname" .context) .appName }}
    {{- if .config.secretName }}
      {{- $secretName = .config.secretName }}
    {{- end }}
    {{- $secretConfigName := printf "%s-secretconfig" $secretName }}
    {{- $secretRefreshInterval := "1m" }}
    {{- if .context.Values.vault.secretRefreshInterval }}
      {{- $secretRefreshInterval = .context.Values.vault.secretRefreshInterval }}
    {{- end }}
    {{- if .config.secretRefreshInterval }}
      {{- $secretRefreshInterval = .config.secretRefreshInterval }}
    {{- end }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $secretConfigName}}
data:
  annotations: |
    last-synced: {{ `{{ now }}` }}

  {{ .appName }}: |
    {{ `{{ $app := "` }}{{ .appName }}{{ `" }}` }}
    {{ `{{ $env := "` }}{{ .context.Values.vault.environment }}{{ `" }}` }}
    {{ `` }}

    {{- range $key := $vaultKeys }}
    {{ `{{ $` }}{{ $key }}{{ `Context := dict "data" (.` }}{{ $key }}{{ ` | fromJson) "env" $env "app" $app "entry" "` }}{{ $key }}{{ `" }}` }}
    {{- end }}

    {{ `
    {{- define "getEnvValue" -}}
      {{- $data := .context.data }}
      {{- range $key := (split "." .key) }}
        {{- if $data }}
          {{- $data = index $data $key }}
        {{- end }}
      {{- end }}

      {{- if $data }}
        {{- if eq "string" (printf "%T" $data) }}
          {{- printf "%s" ($data | replace "'" "''") }}
        {{- else }}
          {{- if index $data .context.env }}
            {{- printf "%s" (index $data .context.env | replace "'" "''") }}
          {{- else }}
            {{- if index $data "default" }}
              {{- printf "%s" (index $data "default" | replace "'" "''") }}
            {{- else }}
              {{- printf "ERROR: [%s][%s] '%s' is not defined neither for '%s' nor default\n" .context.app .context.entry .key .context.env }}
              {{- $error := index nil "key is not set for that specific env and has not default value" }}
            {{- end }}
          {{- end }}
        {{- end }}
      {{- else }}
        {{- printf "ERROR: [%s][%s] Unable to find '%s'\n" .context.app .context.entry .key }}
        {{- $error := index nil "Unable to find the given key" }}
      {{- end }}
    {{- end }}
    ` }}

    {{- range $key, $value := .config.secretConfig }}
      {{- range $secretKey, $secretValue := $value }}
    {{ $secretKey }}{{ `: '{{ template "getEnvValue" (dict "context" $`}}{{ $key }}{{`Context "key" "` }}{{ $secretValue }}{{ `") }}'` }}
      {{- end }}
    {{ `` }}
    {{- end }}
    {{- range $secretKey, $secretValue := .config.templateSecretConfig }}
      {{- $secretValue = regexReplaceAll "{{@([^:]+):([^}]+)}}" $secretValue "{{ template \"getEnvValue\" (dict \"context\" $$${1}Context \"key\" \"${2}\") }}" }}
      {{- if ($secretValue | contains "\n") }}
    {{ $secretKey }}: {{- toYaml $secretValue | indent 4 }}
      {{- else }}
    {{ $secretKey }}: '{{ $secretValue }}'
      {{- end }}
    {{ `` }}
    {{- end }}
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {{ $secretName }}
spec:
  refreshInterval: {{ $secretRefreshInterval }}
  secretStoreRef:
    name: {{ .context.Values.vault.secretStore }}
    kind: {{ default "ClusterSecretStore" .context.Values.vault.secretStoreKind }}
  target:
    name: {{ $secretName }}
    template:
      engineVersion: v2
      type: {{ default "Opaque" .config.secretType }}
      metadata:
        annotations:
          reloader.stakater.com/match: 'true'
          {{- with .config.annotations }}
          {{- toYaml . | nindent 10 }}
          {{- end }}
        labels:
          chart-app: {{ .appName }}
          chart-secret-source: external-secrets
          {{- with .config.labels }}
          {{- toYaml . | nindent 10 }}
          {{- end }}
      templateFrom:
        - target: Data
          configMap:
            name: {{ $secretConfigName}}
            items:
              - key: {{ .appName }}
                templateAs: KeysAndValues
        - target: Annotations
          configMap:
            name: {{ $secretConfigName}}
            items:
              - key: annotations
                templateAs: KeysAndValues
  data:
    {{- range $key := $vaultKeys }}
    - secretKey: {{ $key }}
      remoteRef:
        key: {{ $.context.Values.vault.secretKeyPrefix }}{{ $key }}
    {{- end }}

  {{- end }}
{{- end }}
{{- end }}
