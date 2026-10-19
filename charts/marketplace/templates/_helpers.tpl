{{- define "marketplace.addressesEnv" -}}
- name: APP_ADDRESSES_INTERNATIONAL_ENABLED
  value: {{ .Values.addresses.internationalEnabled | quote }}
- name: APP_ADDRESSES_ALLOWED_COUNTRY_CODES
  value: {{ join "," .Values.addresses.allowedCountryCodes | quote }}
- name: APP_ADDRESSES_DEFAULT_COUNTRY_CODE
  value: {{ .Values.addresses.defaultCountryCode | quote }}
{{- end -}}
