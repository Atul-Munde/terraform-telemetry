#!/bin/zsh
export TF_VAR_elastic_password='Intangles@2026'
export TF_VAR_kibana_encryption_key='Intangles2026RandomSecureKey32!!'
terraform apply -auto-approve -compact-warnings 2>&1
