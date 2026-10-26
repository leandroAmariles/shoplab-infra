# Infraestructura local con Terraform sobre Floci

Esta guía explica cómo levantar y borrar con un solo comando un clúster EKS emulado, con su plataforma base, sin
cuenta de AWS. La decisión de usar Terraform + Floci está en el ADR-0005 del repositorio `shoplab-helpdesk`
(`docs/adr/0005-terraform-floci-eks-local.md`).

## Qué se crea

- **Floci** (emulador de AWS, licencia MIT) en Docker, con la imagen fijada a una versión.
- **Estado remoto** de Terraform en un bucket S3 de Floci, con bloqueo nativo (`use_lockfile`).
- **Clúster EKS emulado** (Floci lo levanta sobre k3s) y su kubeconfig.
- **Secretos** en Secrets Manager y **parámetros** en SSM.
- **Plataforma**: ingress-nginx, External Secrets Operator, kube-prometheus-stack y Argo CD, con una aplicación
  inicial sincronizándose.

## Requisitos

| Herramienta | Notas |
| --- | --- |
| Docker | Con acceso a `/var/run/docker.sock`. Recomendado: 16 GB de RAM en total y 4 CPU; el entorno completo usa varios GB. |
| Terraform | `~> 1.15.8` (mínimo 1.10 por `use_lockfile`). |
| bash | En Windows, Git Bash. Los scripts de `scripts/` solo necesitan bash, Docker y Terraform. |
| make | Opcional: los objetivos del `Makefile` solo llaman a `scripts/*.sh`. |
| kubectl | Opcional, para inspeccionar el clúster. |

No hace falta ninguna credencial de AWS: las que usa el proveedor son ficticias y todo apunta a `localhost:4566`.

## Uso

1. Crea el archivo de valores de secretos (no se versiona):

   ```bash
   cp terraform/envs/dev/secrets.auto.tfvars.example terraform/envs/dev/secrets.auto.tfvars
   # edita los valores; también puedes usar la variable de entorno TF_VAR_secrets
   ```

2. Levanta todo de cero:

   ```bash
   make up          # o: bash scripts/up.sh
   ```

   Hace, en orden: `docker compose up`, espera a Floci, crea el bucket de estado (bootstrap), inicializa el backend
   remoto y ejecuta `terraform apply`. Si se interrumpe, vuelve a ejecutarlo: continúa donde quedó. Tarda unos 4
   minutos con las imágenes ya descargadas.

3. Usa el clúster:

   ```bash
   export KUBECONFIG=terraform/envs/dev/kubeconfig.yaml
   kubectl get pods -A
   kubectl -n argocd get applications
   ```

4. Entra a Argo CD por el ingress:

   ```bash
   kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
   ```

   Abre `http://argocd.localtest.me:8080` con el usuario `admin` (`*.localtest.me` resuelve a 127.0.0.1). Argo CD
   sincroniza `shoplab-root` y, a través de ella, la `Application` de `dev`; el flujo completo está en
   [`gitops.md`](gitops.md).

5. Borra todo:

   ```bash
   make down        # o: bash scripts/down.sh
   ```

   Ejecuta `terraform destroy`, destruye el bucket de estado, apaga Floci y elimina los contenedores y redes que
   Floci crea fuera de compose (`floci-aws-*`). Termina con `scripts/verify-clean.sh`.

## Secretos y parámetros

- Los valores se proporcionan siempre desde fuera del repositorio: `secrets.auto.tfvars` (ignorado por git) o
  `TF_VAR_secrets`. Si faltan, `make up` se detiene antes de levantar nada y explica qué hacer.
- Los secretos se crean en Secrets Manager con el prefijo `/shoplab/<ambiente>/` y los parámetros en SSM.
- El entorno incluye un `ExternalSecret` de demostración en el namespace `demo` que copia
  `/shoplab/dev/postgres-password` a un `Secret` del clúster.
- El estado remoto contiene los valores en claro: vive solo en el emulador local. `make scan` busca credenciales
  en el historial y en los cambios del área de preparación de git (gitleaks vía Docker).

## Versiones

Todo está fijado: Terraform, providers, charts, la imagen de Floci y la de k3s. El archivo `.terraform.lock.hcl`
de cada raíz se versiona e incluye hashes para Windows, Linux y macOS. Para actualizar una versión, cámbiala en el
`versions.tf` o en `variables.tf` correspondiente, ejecuta `terraform init -upgrade` y vuelve a generar los hashes:

```bash
terraform -chdir=terraform/envs/dev providers lock \
  -platform=windows_amd64 -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64
```

`scripts/check-pins.sh` falla si aparece `latest`, una imagen sin tag o un rango abierto.

## Pruebas

```bash
make test               # formato, estructura, pines, terraform test de cada módulo (con mocks) y validate
make test-integration   # aplica un ambiente completo contra Floci con terraform test
make scan               # busca credenciales
```

## Un solo ambiente

Hay un único entorno raíz, `terraform/envs/dev`, con su bucket (`shoplab-tfstate-dev`) y su clave de estado
(`dev/terraform.tfstate`). Los scripts usan la variable `ENV` (por defecto `dev`); solo se cambia para pruebas, como el
ambiente `itest` de `make test-integration`. Para añadir otro ambiente, ver el ADR-0008 del repositorio
`shoplab-helpdesk` (`docs/adr/0008-un-solo-ambiente-dev.md`).

### Pasar desde el entorno `local` anterior

Hasta LAB-101 el entorno raíz se llamaba `local` (clúster `shoplab-local`, bucket `shoplab-tfstate-local`). El cambio de
nombre no se migra: el estado vive en un Floci desechable. Si tenías ese entorno levantado:

1. Antes de actualizar el repositorio, destrúyelo con la versión anterior: `make down` (o, si no responde,
   `docker compose down -v --remove-orphans`). Termina con `bash scripts/verify-clean.sh`.
2. Actualiza el repositorio. Copia `secrets.auto.tfvars` de `terraform/envs/local/` a `terraform/envs/dev/` (el archivo está
   ignorado por git y `git pull` no lo mueve; si falta, créalo desde `secrets.auto.tfvars.example`).
3. Levanta de nuevo con `make up`. Se pierden los datos del clúster anterior (Postgres y modelos de Ollama), igual que
   con cualquier `make down`.

## Modo de respaldo con kind

Si el EKS de Floci falla, el módulo `eks` puede crear el clúster con kind y exponer el mismo contrato de salida;
el módulo `platform` no cambia:

```bash
CLUSTER_MODE=kind make up
```

En este modo no se crea ningún clúster EKS emulado. En modo por defecto (`floci`) no se crea ningún clúster de kind.

## Solución de problemas

| Síntoma | Causa y solución |
| --- | --- |
| `Floci no responde en http://localhost:4566` | El contenedor no arrancó o el puerto 4566 está ocupado por otro emulador. Revisa `docker ps` y detén el otro proceso. |
| `Error acquiring the state lock` | Hay otra operación sobre el mismo estado. Espera a que termine. Si quedó huérfano tras un fallo: `terraform -chdir=terraform/envs/dev force-unlock <ID>` con el ID que muestra el error. |
| Floci se reinició y perdió su contenido | El estado remoto referencia recursos que ya no existen. Ejecuta `make down` (limpia contenedores aunque Floci no responda) y vuelve a `make up`. |
| `make down` falla a medias | Es reintentable: vuelve a ejecutarlo; el error indica el recurso que falló. |
| Pods de External Secrets no llegan a Floci | Los pods de k3s no resuelven nombres de contenedor ni `host.docker.internal`; el entorno usa la IP de Floci en la red de compose (`scripts/floci-ip.sh`). |
| `node-exporter` ausente | Se desactiva a propósito: falla con `CreateContainerError` en k3s dentro de Docker. |
| ingress-nginx | Su proyecto está en retiro; la última versión del chart es la 4.15.1. Es aceptable en un laboratorio local. |
| Git Bash y rutas | Los scripts exportan `MSYS_NO_PATHCONV=1`; si ejecutas `docker exec` a mano con rutas, haz lo mismo. |

## Por qué el kubeconfig usa el certificado de k3s

Floci valida los tokens de `aws eks get-token` con un webhook, pero el token que genera el proveedor de Terraform
(`aws_eks_cluster_auth`) sale con `X-Amz-Expires=0` y la API de k3s responde `401`. Por eso el módulo `eks` lee el
certificado de cliente de `/etc/rancher/k3s/k3s.yaml` del contenedor `floci-aws-eks-<cluster>`
(`terraform/modules/eks/scripts/k3s-kubeconfig.sh`). Requiere la CLI de Docker en la misma máquina.
