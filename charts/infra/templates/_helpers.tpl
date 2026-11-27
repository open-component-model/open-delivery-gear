{{/*
ODG Infra helper templates.
*/}}

{{/* BTP account provider config name (fixed; referenced by all BTP resources). */}}
{{- define "infra.providerConfigName" -}}
account-provider-config
{{- end -}}

{{/* Subaccount resource name (used for subaccountRef across BTP resources). */}}
{{- define "infra.subaccountRef" -}}
{{ .Values.subaccount.name }}
{{- end -}}

{{/*
IAS tenant host, the single source of truth for all IAS-derived URLs. Required whenever an
IAS-backed feature (cloudLogging.saml / shootOidc) is enabled.
*/}}
{{- define "infra.ias.tenantHost" -}}
{{- required "ias.tenantHost is required when an IAS feature is enabled" .Values.ias.tenantHost -}}
{{- end -}}

{{/* SAML IdP metadata URL: explicit cloudLogging.saml.idp.metadataUrl, else derived. */}}
{{- define "infra.ias.samlMetadataUrl" -}}
{{- with .Values.cloudLogging.saml.idp.metadataUrl -}}{{ . }}{{- else -}}https://{{ include "infra.ias.tenantHost" $ }}/saml2/metadata{{- end -}}
{{- end -}}

{{/* SAML IdP entity ID: explicit cloudLogging.saml.idp.entityId, else derived. */}}
{{- define "infra.ias.samlEntityId" -}}
{{- with .Values.cloudLogging.saml.idp.entityId -}}{{ . }}{{- else -}}https://{{ include "infra.ias.tenantHost" $ }}{{- end -}}
{{- end -}}

{{/* OIDC issuer URL: explicit shootOidc.issuerUrl, else derived (trailing slash). */}}
{{- define "infra.ias.oidcIssuerUrl" -}}
{{- with .Values.shootOidc.issuerUrl -}}{{ . }}{{- else -}}https://{{ include "infra.ias.tenantHost" $ }}/{{- end -}}
{{- end -}}
