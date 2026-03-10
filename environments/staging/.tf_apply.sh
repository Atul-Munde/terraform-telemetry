#!/bin/zsh

export TF_VAR_elastic_password='Intangles@2026'
export TF_VAR_kibana_encryption_key='Intangles2026RandomSecureKey32!!'
export TF_VAR_dash0_auth_token='Bearer auth_uPbyf1XkiclCTALKB7YsniymdTBcUAXB'

terraform apply -compact-warnings "$@" 2>&1
