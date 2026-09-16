# Container Image Publishing

The [`container` workflow](../.github/workflows/container.yml) builds the image
from the repo-root [`Dockerfile`](../Dockerfile) on every push to `main` and
pushes it to Azure Container Registry as:

```
easysoft.azurecr.io/securevibes:latest
easysoft.azurecr.io/securevibes:<commit-sha>
```

This only publishes to the Azure Container Registry — it does not publish to
GitHub Container Registry (ghcr.io).

## Required secrets

The workflow authenticates to the registry with a single Microsoft Entra ID
(Azure AD) **service principal**, scoped to nothing more than pushing images
to this one registry:

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | The service principal's Application (client) ID |
| `AZURE_CLIENT_SECRET` | The service principal's client secret |

Both are repository secrets under
**Settings → Secrets and variables → Actions → New repository secret** on the
`easySoft-GmbH/securevibes` GitHub repo.

## Generating the service principal

You need `az` CLI access with permission to create service principals and
assign roles on the `easysoft` registry's resource group. Replace
`<subscription-id>` and `<resource-group>` below.

```bash
az login

az ad sp create-for-rbac \
  --name "securevibes-ci-acr-push" \
  --role AcrPush \
  --scopes "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.ContainerRegistry/registries/easysoft" \
  --years 1
```

This prints JSON like:

```json
{
  "appId": "00000000-0000-0000-0000-000000000000",
  "displayName": "securevibes-ci-acr-push",
  "password": "<client-secret>",
  "tenant": "00000000-0000-0000-0000-000000000000"
}
```

Map the output to the GitHub secrets:

- `appId` → `AZURE_CLIENT_ID`
- `password` → `AZURE_CLIENT_SECRET`

The `password` is only ever shown once at creation time — copy it into the
GitHub secret immediately, it cannot be retrieved again later.

### Why `AcrPush` and not `Contributor`/`Owner`

`AcrPush` is the least-privileged built-in role that allows pushing (and
pulling) images. It cannot delete the registry, change its network rules, or
touch other Azure resources. Do not widen the role or the scope beyond the
single registry unless a real requirement shows up.

## Setting the GitHub secrets

Via the GitHub UI: repo → **Settings** → **Secrets and variables** →
**Actions** → **New repository secret**, once each for `AZURE_CLIENT_ID` and
`AZURE_CLIENT_SECRET`.

Via the GitHub CLI (from a checkout of the repo):

```bash
gh secret set AZURE_CLIENT_ID --body "<appId>"
gh secret set AZURE_CLIENT_SECRET --body "<password>"
```

## Rotating / expiring credentials

The service principal's secret was created with `--years 1` above, so it
expires automatically. To rotate it before expiry (or immediately, if it may
have leaked):

```bash
az ad sp credential reset \
  --id <appId> \
  --years 1
```

This invalidates the previous secret and prints a new one — update the
`AZURE_CLIENT_SECRET` GitHub secret with it right away, since the workflow
will start failing to authenticate until you do.

To fully decommission access (e.g. the CI pipeline is retired), delete the
service principal instead of just letting the secret expire:

```bash
az ad sp delete --id <appId>
```

## Troubleshooting

- **`unauthorized: authentication required` on push** — the secret has
  expired or was rotated without updating the GitHub secret; reset the
  credential and update `AZURE_CLIENT_SECRET`.
- **`403 Forbidden` from the registry** — the service principal's role
  assignment on the registry was removed, or scoped to the wrong resource;
  re-run the `az ad sp create-for-rbac`/role-assignment step above.
- **Workflow doesn't trigger** — it only runs on pushes to `main`; a PR from
  a fork or a push to another branch will not publish an image.
