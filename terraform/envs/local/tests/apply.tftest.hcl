# Integración contra Floci (necesita el emulador levantado): se ejecuta con scripts/test-integration.sh.
# Usa el ambiente "itest" para no chocar con el clúster "shoplab-local" y destruye todo al terminar.
variables {
  environment = "itest"
  secrets = {
    postgres-password = "valor-de-prueba-1"
    llm-api-key       = "valor-de-prueba-2"
  }
}

run "applies_cluster_and_platform_from_scratch" {
  command = apply

  assert {
    condition     = length(output.installed_components) == 4
    error_message = "Deben instalarse los cuatro componentes de plataforma"
  }

  assert {
    condition = alltrue([
      for name in ["ingress-nginx", "external-secrets", "kube-prometheus-stack", "argo-cd"] :
      contains(keys(output.installed_components), name)
    ])
    error_message = "Faltan componentes de plataforma en installed_components"
  }

  assert {
    condition     = output.argocd_url != ""
    error_message = "Debe exponerse argocd_url"
  }

  assert {
    condition     = module.secrets.secret_names != null && length(module.secrets.secret_names) == 2
    error_message = "Deben crearse los dos secretos requeridos en Secrets Manager"
  }
}
