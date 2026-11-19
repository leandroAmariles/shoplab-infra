# Gateway de modelos en el clúster (LAB-84)

El backend de `dev` ya no habla con Ollama: toda llamada a un modelo pasa por **LiteLLM** (`svc/litellm:4000`), que decide qué
modelo responde, cae a un modelo de respaldo, aplica un presupuesto por clave virtual y deja en sus logs los tokens y el coste.
La decisión y el diseño están en `shoplab-helpdesk` (ADR-0023 y `docs/gateway-de-modelos.md`); aquí solo lo propio del clúster.

| Recurso | Qué es |
|---|---|
| `Deployment litellm` + `Service litellm:4000` | El gateway (imagen de versión fija). Sin `Ingress`. |
| `StatefulSet litellm-postgres` (PVC `local-path`, 1 GiB) | Su estado propio: claves virtuales y gasto. |
| `ConfigMap litellm-files` | `config.yaml`, `keys.yaml` y los scripts; se genera desde `k8s/base/litellm/files/`. |
| `Job litellm-bootstrap-keys` (hook `PostSync` de Argo CD) | Crea o actualiza las claves virtuales; idempotente. |
| `ExternalSecret litellm-credentials` | `/shoplab/dev/litellm`: `LITELLM_MASTER_KEY`, `LITELLM_KEY_BACKEND`, `LITELLM_KEY_INGEST`, `LITELLM_KEY_EVAL` (la de la evaluación de calidad, LAB-29), `POSTGRES_PASSWORD` y, opcional, `CLOUD_PROVIDER_API_KEY`. |
| `ExternalSecret backend-litellm` | Entrega la clave virtual del backend (`SPRING_AI_OPENAI_API_KEY`). |
| `NetworkPolicy` | Solo `backend`, `ingest` y el Job llegan a `litellm`; solo `litellm` llega a su Postgres. En `dev`, `backend` e `ingest` no pueden salir hacia el puerto de Ollama del host. |

## Secretos

Crea el secreto JSON **antes** de sincronizar (con valores `sk-...` reales, sin marcadores `change-me`/`local`: el Job los rechaza en
`dev`). Terraform lo declara en `terraform/modules/secrets` (`litellm`) y `secrets.auto.tfvars.example` muestra la forma.
`CLOUD_PROVIDER_API_KEY` es opcional: sin ella no existe el modelo `chat-cloud` y el gateway no sale a Internet.

`LITELLM_KEY_EVAL` es **obligatoria** desde LAB-29: el Job `litellm-bootstrap-keys` aborta si falta la variable de una clave de
`keys.yaml`, y sin el Job el gateway queda sin claves. En local no hay que escribirla a mano: `make secrets` (que `make up` ya
ejecuta) completa `secrets.auto.tfvars` con lo que falte (`langfuse`, `litellm` y la clave `eval`, con valores aleatorios en el
formato que exigen el gateway y Langfuse). Solo **añade**: nunca cambia un valor existente (p. ej. `postgres-password`, que
debe coincidir con tu Postgres de Docker) y no imprime ningún valor. Tras añadir claves hay que repetir `make up` para que
Terraform las suba a Secrets Manager y External Secrets las sincronice.

## Medición de calidad de las respuestas (LAB-29)

`make quality` ejecuta `python -m shoplab_eval quality` de `shoplab-helpdesk/eval` contra el ingress, con el gateway como juez
(modelo lógico `judge`, clave virtual `eval`: solo llama a `judge` y `embeddings`) y Langfuse para adjuntar las puntuaciones a
las trazas. Las claves salen de los Secrets del clúster y viajan por variables de entorno: no se imprimen. Requiere `make up`,
`make seed`, los túneles de `make forward` (LiteLLM `localhost:4000`, Langfuse `localhost:3001`) y el modelo del juez en el
Ollama del host (`qwen2.5:7b`; descárgalo con `OLLAMA_JUDGE_MODEL=qwen2.5:7b` en `shoplab-helpdesk/infra/.env` o `ollama pull`).
Argumentos de la medición: `make quality ARGS="--run-id demo-1 --no-langfuse"`. Los CSV quedan en `shoplab-helpdesk/eval/results/`.

## Configuración compartida con docker compose

La configuración del gateway vive en `shoplab-helpdesk/infra/litellm/`. Tras cambiarla, ejecuta
`scripts/sync-litellm-files.sh` (copia los archivos a `k8s/base/litellm/files/` y guarda el commit de origen en `SOURCE`) y haz commit
del resultado. El hash del `ConfigMap` reinicia el gateway al sincronizar.

## Ollama del host

En `dev` Ollama corre en el Docker del host (`overlays/dev/ollama-host.yaml`) y el clúster llega por `172.17.0.1:11434`. Como en
`shoplab-helpdesk` Ollama ya no publica puerto por defecto, levántalo con:

```bash
docker compose -f infra/docker-compose.yml -f infra/docker-compose.ollama-host.yml up -d ollama
```

## Uso

```bash
kubectl -n shoplab-dev get pods -l app.kubernetes.io/name=litellm
kubectl -n shoplab-dev get job litellm-bootstrap-keys
kubectl -n shoplab-dev port-forward svc/litellm 4000:4000            # acceso al gateway (no hay Ingress)
# Tokens y coste de una conversación (una línea JSON por petición, sin contenido):
kubectl -n shoplab-dev logs deploy/litellm | jq -s --arg c "<conversation-id>" '
  map(select(.event=="llm_request" and .conversation_id==$c))
  | {turns: length, prompt_tokens: (map(.prompt_tokens // 0) | add), completion_tokens: (map(.completion_tokens // 0) | add),
     cost_usd: (map(.cost_usd // 0) | add), unpriced_or_unknown: (map(select(.cost_status!="priced")) | length)}'
```

Tras `destroy` y `apply`, Argo CD vuelve a dejar el gateway funcionando y el Job recrea las claves sin pasos manuales. El gasto
acumulado del periodo vive en el PVC de `litellm-postgres`: si el volumen se pierde, las claves y los presupuestos se recrean
desde `keys.yaml` y el gasto vuelve a cero.

## Pendiente de verificar en el clúster

Estos manifiestos se validaron renderizando el overlay con kustomize; no se han desplegado aún. Al desplegar, comprobar: la memoria real
del gateway junto a Langfuse en el nodo único (los `requests` son mínimos), que el CNI del clúster aplique las `NetworkPolicy`
(también las de salida) y que el Job `litellm-bootstrap-keys` termine tras el primer sync.
