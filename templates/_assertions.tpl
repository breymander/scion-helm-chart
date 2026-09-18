{{/*
Render-time guards. Each one turns a mistake that would otherwise surface as a
running-but-broken hub into a message at `helm install` time.
*/}}
{{- define "scion.assert" -}}

{{- /* baseUrl: absolute and https. The hub enforces https itself and builds
       its OAuth redirect_uri from this value. */ -}}
{{- $u := urlParse .Values.hub.baseUrl -}}
{{- if ne $u.scheme "https" -}}
{{- fail (printf "hub.baseUrl must be an absolute https:// URL; got %q. The hub refuses a non-https base URL in hosted mode, and it builds its OAuth redirect_uri from this value." .Values.hub.baseUrl) -}}
{{- end -}}
{{- if not $u.host -}}
{{- fail (printf "hub.baseUrl has no host; got %q." .Values.hub.baseUrl) -}}
{{- end -}}

{{- /* userAccessMode: only three values are implemented. Upstream's
       settings.yaml.example documents "allowlist", which is not one of them
       and falls through to open - the exact opposite of the intent. */ -}}
{{- $modes := list "invite_only" "domain_restricted" "open" -}}
{{- if not (has .Values.auth.userAccessMode $modes) -}}
{{- fail (printf "auth.userAccessMode must be one of %s; got %q. Note that upstream's settings.yaml.example documents \"open\"/\"domain\"/\"allowlist\", but checkUserAuthorized only switches on \"invite_only\" and \"domain_restricted\" - every other value, including \"allowlist\", falls through to its default branch and lets ANYONE your identity provider authenticates log in." (join ", " $modes) .Values.auth.userAccessMode) -}}
{{- end -}}

{{- if eq .Values.auth.userAccessMode "open" -}}
{{- if not .Values.auth.acknowledgeOpenAccess -}}
{{- fail "auth.userAccessMode is \"open\", which lets anyone your identity provider authenticates log in and have the hub run containers with your model credentials. With a GitHub OAuth app that is every GitHub user. If that is genuinely what you want, set auth.acknowledgeOpenAccess: true." -}}
{{- end -}}
{{- end -}}

{{- if eq .Values.auth.userAccessMode "domain_restricted" -}}
{{- if not .Values.auth.authorizedDomains -}}
{{- fail "auth.userAccessMode is \"domain_restricted\" but auth.authorizedDomains is empty. The hub logs a warning and blocks every user, including the ones in hub.adminEmails' domains." -}}
{{- end -}}
{{- end -}}

{{- /* The lockout case, and the reason it is checked only on install: with
       invite_only and no super-admin, a FRESH hub has nobody who can log in,
       and invitations can only be issued from inside. An existing deployment
       may legitimately have its admins in the database already. */ -}}
{{- if and .Release.IsInstall (eq .Values.auth.userAccessMode "invite_only") (not .Values.hub.adminEmails) -}}
{{- fail "auth.userAccessMode is \"invite_only\" but hub.adminEmails is empty, so this fresh install would have no one who can log in - and invitations can only be sent by someone already inside. Set hub.adminEmails to the email address your identity provider returns for you." -}}
{{- end -}}

{{- /* OAuth needs a complete web client, and a half-configured one is not a
       startup failure: the hub comes up green and answers every login with
       "OAuth provider is not configured". */ -}}
{{- if eq .Values.auth.mode "oauth" -}}
{{- $gh := .Values.auth.oauth.github -}}
{{- $g := .Values.auth.oauth.google -}}
{{- $ghOk := and $gh.clientId $gh.clientSecret -}}
{{- $gOk := and $g.clientId $g.clientSecret -}}
{{- if not (or $ghOk $gOk) -}}
{{- if or $gh.clientId $gh.clientSecret $g.clientId $g.clientSecret -}}
{{- fail "auth.mode is \"oauth\" but a provider has only half a credential. Set BOTH clientId and clientSecret for github or for google - the hub copies these in without validating them, so an incomplete pair is not a startup error: the hub comes up healthy and answers every login attempt with \"OAuth provider is not configured\"." -}}
{{- else -}}
{{- fail "auth.mode is \"oauth\" but no provider credentials are set. Configure auth.oauth.github or auth.oauth.google with both clientId and clientSecret, or switch auth.mode to \"proxy\" if something in front of the hub authenticates users." -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- /* sqlite is the only driver this chart supports, and the reason is not
       taste: postgres makes the hub take its HA code path. */ -}}
{{- if ne .Values.database.driver "sqlite" -}}
{{- fail (printf "database.driver must be \"sqlite\"; got %q. Setting postgres makes the hub's isHADeployment test true, which runs a hosted-HA preflight that upstream documents as unlanded, and the hub aborts before it serves anything." .Values.database.driver) -}}
{{- end -}}

{{- if ne .Values.storage.provider "local" -}}
{{- fail (printf "storage.provider must be \"local\"; got %q. The gcs provider needs a Cloud Storage bucket and ambient Google credentials, which is the GKE shape this chart deliberately does not carry." .Values.storage.provider) -}}
{{- end -}}

{{- /* A ReadWriteOnce claim cannot back more than one writer, and the hub is
       a single writer by design. Caught here because a multi-node RWX
       misconfiguration is otherwise only visible as database corruption. */ -}}
{{- if and .Values.persistence.enabled .Values.persistence.existingClaim .Values.persistence.storageClass -}}
{{- fail "persistence.existingClaim and persistence.storageClass are both set, but an existing claim already has a storage class. Set one or the other." -}}
{{- end -}}

{{- end }}
