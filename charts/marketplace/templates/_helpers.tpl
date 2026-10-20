{{- define "marketplace.addressesEnv" -}}
- name: APP_ADDRESSES_INTERNATIONAL_ENABLED
  value: {{ .Values.addresses.internationalEnabled | quote }}
- name: APP_ADDRESSES_ALLOWED_COUNTRY_CODES
  value: {{ join "," .Values.addresses.allowedCountryCodes | quote }}
- name: APP_ADDRESSES_DEFAULT_COUNTRY_CODE
  value: {{ .Values.addresses.defaultCountryCode | quote }}
{{- end -}}

{{/* Viper decodes string slices from CSV; an empty string explicitly clears defaults. */}}
{{- define "marketplace.sellerImportEnv" -}}
- name: APP_PRODUCT_IMPORT_SELLER_IMAGE_MODE
  value: {{ .Values.productImport.sellerImageMode | quote }}
- name: APP_PRODUCT_IMPORT_SELLER_GENERATED_IMAGE_ROLES
  value: {{ join "," .Values.productImport.sellerGeneratedImageRoles | quote }}
{{- end -}}
