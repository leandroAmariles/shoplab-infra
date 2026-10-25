# shoplab-infra

Infraestructura como código de ShopLab Helpdesk (LAB-98): Terraform contra un AWS emulado en local (Floci)
con un EKS local, ingress-nginx, External Secrets Operator, Argo CD y kube-prometheus-stack.

- Código: `terraform/` (módulos `state`, `eks`, `secrets`, `platform` y un entorno raíz por ambiente en `envs/`)
- Guía: `docs/terraform-local.md`
- Especificación: `specs/LAB-98-terraform-floci-eks/` en el repositorio `shoplab-helpdesk`

Uso previsto: `make up` levanta todo de cero; `make down` lo borra.
