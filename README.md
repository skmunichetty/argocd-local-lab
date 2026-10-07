# Hello Argo CD — local GitOps lab

A small React + .NET app deployed to a **local** Kubernetes cluster by **Argo CD**, using **Kustomize**.
Everything runs on your Windows laptop inside Docker Desktop. Nothing is created in AWS or any remote cluster.
The only remote piece is the Git repository on GitHub, which Argo CD reads from.

```
 your laptop
 ┌──────────────────────────────────────────────────────────────────────────┐
 │  docker build ──► image ──kind load──►┌─ kind cluster "argocd-lab" ─────┐│
 │                                       │  (a Docker container)           ││
 │  git push ──► GitHub ◄──── clones ────┤  argocd namespace: Argo CD      ││
 │                                       │        │ applies manifests      ││
 │                                       │        ▼                        ││
 │  browser ──port-forward──────────────►│  hello-app namespace:           ││
 │  localhost:9080                       │   web (nginx+React) ─► api(.NET)││
 │                                       └─────────────────────────────────┘│
 └──────────────────────────────────────────────────────────────────────────┘
```

**Two separate jobs. Keep them apart in your head:**

| | Building images (you, manually for now) | Deploying (Argo CD) |
|---|---|---|
| What | Turn source code into a container image with a unique tag, and copy it into the cluster's image store | Make the cluster match the manifests in Git |
| Tools | `docker build`, `kind load docker-image` | Argo CD watching `deploy/overlays/local` on `main` |
| Changes the cluster? | **No.** A loaded image sits unused until something references its tag | **Yes.** Creates/updates/deletes Kubernetes objects |
| Trigger | You run `scripts\build-and-load.ps1` | You `git push` a change to the overlay |

So shipping a new version = **build + load** a new tag, then **commit + push** the new tag. Argo CD does the rest.
(Later, GitHub Actions will do the build step and push to a registry instead of `kind load`.)

---

## 1. Prerequisites

Checked on this machine on 2026-10-07:

| Tool | Version found | Notes |
|---|---|---|
| Docker Desktop | Engine 27.3.1 (WSL2, **cgroup v1**) | Must be running |
| kubectl | 1.31 (built-in Kustomize 5.4.2) | Fine; within ±1 minor of the cluster |
| kind | 0.24 on PATH (too old), **0.33.0 in `.tools\kind.exe`** | Use `.\.tools\kind.exe` everywhere |
| Git | 2.50 | |
| GitHub CLI `gh` | 2.76, logged in as `skmunichetty` | Used to create the repo |
| .NET SDK / Node.js | 10.0 / 24 | Only needed to run the app outside Docker |

Pinned versions used by this lab:

- **Argo CD v3.5.4** (latest stable on 2026-10-07; tested with Kubernetes 1.33–1.36)
- **Kubernetes v1.34.11** via `kindest/node` (see `kind/cluster.yaml` for why not 1.35)

`.tools\kind.exe` is git-ignored. If you clone this repo elsewhere, download kind v0.33.0 from
https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0 (`kind-windows-amd64`) into `.tools\kind.exe`.

All commands below are for **Windows PowerShell**, run from the repo root (`C:\Sample Projects\ArgoCD`).

---

## 2. Folder structure

```
.
├── README.md
├── .gitignore
├── src/
│   ├── api/                      .NET 10 minimal API
│   │   ├── Program.cs            GET /api/hello, /healthz/live, /healthz/ready
│   │   ├── HelloApi.csproj
│   │   └── Dockerfile            2-stage: SDK builds, small aspnet runtime runs (non-root, port 8080)
│   └── web/                      React (Vite) frontend
│       ├── src/App.jsx           Calls /api/hello and shows the result
│       ├── nginx/default.conf.template   Serves the page, proxies /api/* to the "api" Service
│       └── Dockerfile            2-stage: Node builds static files, nginx-unprivileged serves them
├── deploy/
│   ├── base/                     Environment-neutral Kubernetes objects
│   │   ├── kustomization.yaml    Lists resources, common labels, generated ConfigMaps
│   │   ├── api-deployment.yaml   API pods: probes, resources, non-root
│   │   ├── api-service.yaml      Stable in-cluster name "api:8080"
│   │   ├── web-deployment.yaml   Frontend pods
│   │   └── web-service.yaml      Stable in-cluster name "web:8080"
│   └── overlays/
│       └── local/                ★ What Argo CD deploys
│           ├── kustomization.yaml   Namespace, IMAGE TAGS, REPLICAS, config overrides
│           └── namespace.yaml       The hello-app namespace
├── argocd/
│   └── hello-app.yaml            The Argo CD Application (applied once with kubectl)
├── kind/
│   └── cluster.yaml              Local cluster definition (pinned node image)
└── scripts/
    └── build-and-load.ps1        Build both images + kind load + write tag into the overlay
```

### What each Kubernetes file does

- **`deploy/base/kustomization.yaml`**: the table of contents. It also *generates* two ConfigMaps
  (`api-config`, `web-config`). Kustomize adds a hash to their names (e.g. `api-config-4t57mmhhm9`),
  so editing a value produces a new name, which makes the Deployment roll out new pods automatically.
- **`api-deployment.yaml` / `web-deployment.yaml`**: "run N copies of this image". Each has:
  - `readinessProbe`: Kubernetes only sends traffic to a pod once this URL returns 200.
  - `livenessProbe`: if this keeps failing, Kubernetes restarts the container.
  - `resources`: `requests` is what the scheduler reserves, `limits` is the hard cap.
  - `securityContext`: refuses to run as root.
  - `imagePullPolicy: IfNotPresent`: use the image already in the node (loaded by kind) instead of
    trying to download it from Docker Hub.
- **`api-service.yaml` / `web-service.yaml`**: a fixed name and IP that load-balance across pods.
  `ClusterIP` means reachable only inside the cluster. You reach it from the laptop with `port-forward`.
- **`overlays/local/kustomization.yaml`**: takes the base and sets the namespace, **image tags**,
  **replica counts**, and `APP_ENVIRONMENT=local-kind`. Almost every exercise edits this one file.
- **`argocd/hello-app.yaml`**: tells Argo CD "deploy `deploy/overlays/local` from branch `main` of
  `https://github.com/skmunichetty/argocd-local-lab.git` into namespace `hello-app`, automatically".

Preview exactly what will be deployed (no cluster changes):

```powershell
kubectl kustomize deploy/overlays/local
```

### How the browser reaches the API

The browser only talks to the **web** pod (`http://localhost:9080`). The page calls the *relative* URL
`/api/hello`; nginx in the web pod forwards `/api/*` to `http://api:8080` (the API Service, set by
`API_UPSTREAM` in the `web-config` ConfigMap). Same origin, so no CORS configuration is needed.

---

## 3. First-time setup

> ✅ = already done for you on 2026-10-07. Re-run only if you are rebuilding from scratch.

### Step 0: Make sure kubectl points at the LOCAL cluster

Your kubeconfig also contains an **AWS EKS** context. Always check before changing anything:

```powershell
kubectl config use-context kind-argocd-lab
kubectl config current-context        # must print: kind-argocd-lab
kubectl cluster-info                  # must show https://127.0.0.1:<port>
```

### Step 1: Create the cluster ✅

```powershell
.\.tools\kind.exe create cluster --config kind/cluster.yaml
kubectl get nodes                     # argocd-lab-control-plane   Ready
```

### Step 2: Install Argo CD v3.5.4 ✅

Official method (https://argo-cd.readthedocs.io/en/stable/getting_started/), pinned to a version
instead of `stable`. `--server-side` is required because some Argo CD CRDs are too big for a normal apply.

```powershell
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.4/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server
kubectl -n argocd get pods            # all Running
```

### Step 3: Open the Argo CD UI (local only)

In a **separate** PowerShell window (leave it running):

```powershell
kubectl port-forward -n argocd svc/argocd-server 9443:443
```

`port-forward` listens on `127.0.0.1` only, so nothing is exposed to your network.
Open **https://localhost:9443**. Your browser will warn about the self-signed certificate; that's expected
locally, so continue.

Username: `admin`. Get the initial password:

```powershell
$b64 = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
```

(It is randomly generated per install and lives only in the cluster. Don't commit it.)

### Step 4: Build images and load them into the cluster ✅ (first tag: `20261007-224155`)

```powershell
.\scripts\build-and-load.ps1
```

This does three things:
1. `docker build` both images with the same unique tag (a timestamp like `20261007-224155`).
   The tag is also baked into the app, so the web page shows which version is running.
2. `kind load docker-image ...` copies the images from Docker Desktop's image store **into the kind node**.
   The kind node is a separate machine as far as images go: without this step pods fail with
   `ErrImagePull`, because Kubernetes would try to download `hello-api` from Docker Hub.
3. Writes the new tag into `deploy/overlays/local/kustomization.yaml`.

Why unique tags instead of `latest`? Kubernetes only rolls out new pods when the pod spec changes.
A new tag in Git = a visible change = a rollout, plus you can always see and revert exactly what's running.

### Step 5: Put the repo on GitHub ✅

```powershell
git init -b main
git add .
git commit -m "Initial Argo CD local lab"
gh repo create skmunichetty/argocd-local-lab --public --source . --push
```

The repo is **public**, so Argo CD can clone it without credentials. Argo CD runs inside the cluster and
can't read `C:\Sample Projects\...`; it only sees what's pushed to GitHub.

<details>
<summary>If you ever make the repo private</summary>

Create a GitHub fine-grained token with **read-only "Contents"** access to just this repo, then register
it in the cluster (stored as a Kubernetes Secret, never in Git):

```powershell
$token = Read-Host "GitHub read-only token"
kubectl -n argocd create secret generic repo-argocd-local-lab --from-literal=type=git --from-literal=url=https://github.com/skmunichetty/argocd-local-lab.git --from-literal=username=skmunichetty --from-literal=password=$token
kubectl -n argocd label secret repo-argocd-local-lab argocd.argoproj.io/secret-type=repository
```
</details>

### Step 6: Create the Argo CD Application ✅

**About pruning (read before relying on it):** `prune: true` means that if a manifest is *removed* from Git,
Argo CD deletes that object from the cluster. Without pruning, it would keep running as an "orphan" and
Argo CD would only flag the app as OutOfSync. Pruning keeps the cluster an exact mirror of Git, but a
mistaken file deletion or rename in Git deletes the live object too. It only affects objects this
Application created. `selfHeal: true` similarly reverts manual `kubectl` changes.

```powershell
kubectl apply -f argocd/hello-app.yaml
kubectl -n argocd get applications    # SYNC STATUS: Synced   HEALTH STATUS: Healthy
kubectl -n hello-app get pods         # 2 x api, 1 x web, all Running 1/1
```

This is the only `kubectl apply` you run for the app. From now on, **Git is the control panel.**

### Step 7: Use the app

In separate windows (leave them running):

```powershell
kubectl port-forward -n hello-app svc/web 9080:8080
```
```powershell
kubectl port-forward -n hello-app svc/api 9081:8080
```

- Frontend: **http://localhost:9080** (shows the API's response and which pod answered)
- API directly: **http://localhost:9081/api/hello**

You only need the `web` port-forward for the app; the `api` one is for poking the API directly.

---

## 4. Everyday workflow

```powershell
# 1. Change code in src/...
# 2. Build + load a new tag and write it into the overlay
.\scripts\build-and-load.ps1
# 3. Review and push. Pushing is what deploys.
git diff
git commit -am "Deploy new version"
git push
# 4. Watch Argo CD pick it up (it polls GitHub about every 3 minutes)
kubectl -n argocd get application hello-app -w
```

Don't want to wait 3 minutes? Ask Argo CD to check Git now:

```powershell
kubectl -n argocd annotate application hello-app argocd.argoproj.io/refresh=normal --overwrite
```

(or click **Refresh** in the UI).

---

## 5. Learning exercises

Keep the Argo CD UI open while you do these. Watching the resource tree change is half the lesson.

### Exercise 1: Ship a new version through Git
1. Edit `src/api/Program.cs`, e.g. change `"Hello from .NET"` or add a field to the response.
   Or change the `<h1>` in `src/web/src/App.jsx`.
2. `.\scripts\build-and-load.ps1`, which prints the new tag.
3. `git diff`: only the two `newTag` lines in the overlay changed (plus your code).
4. `git commit -am "Exercise 1: new greeting"` then `git push`, then refresh.
5. Watch new pods start and old ones stop (rolling update). Reload http://localhost:9080 and the
   version shown matches the new tag.
   (If the web port-forward dies when its pod is replaced, just restart it.)

### Exercise 2: Scale through Git
1. In `deploy/overlays/local/kustomization.yaml` change `api` `count: 2` to `count: 3`.
2. Commit + push + refresh, then `kubectl -n hello-app get pods`: three API pods.
3. Click "Call the API again" a few times: the "Answered by pod" name changes (load balancing).

### Exercise 3: Manual change vs self-healing
```powershell
kubectl -n hello-app scale deploy/api --replicas=6
kubectl -n hello-app get pods -w      # Ctrl+C to stop watching
```
Within seconds Argo CD notices the live state differs from Git and scales back to the Git value.
Try `kubectl -n hello-app delete svc api`: it gets recreated too.
**Lesson:** with self-heal on, `kubectl` edits are temporary; Git wins.

### Exercise 4: Break it with a bad image tag
1. In the overlay, set the `hello-api` `newTag` to `"does-not-exist"`. Commit + push + refresh.
2. Diagnose:
   ```powershell
   kubectl -n argocd get application hello-app       # Synced, but Health: Progressing (later Degraded)
   kubectl -n hello-app get pods                     # new pod: ErrImagePull / ImagePullBackOff
   kubectl -n hello-app describe pod -l app.kubernetes.io/name=api   # read "Events" at the bottom
   ```
   The events say the image `docker.io/library/hello-api:does-not-exist` couldn't be pulled: the tag was
   never built or loaded into kind.
3. Notice the app **still works**: the rolling update keeps old pods running until a new one is Ready.
   That's what readiness probes and rolling updates buy you.

### Exercise 5: Roll back by reverting Git
```powershell
git log --oneline -3
git revert --no-edit HEAD     # creates a new commit that undoes the bad tag
git push
kubectl -n argocd annotate application hello-app argocd.argoproj.io/refresh=normal --overwrite
```
Argo CD goes back to Synced + Healthy with the previous tag. The broken pod disappears.
**Lesson:** rollback is just another Git commit, so the history shows who changed what and when.
(Argo CD's own "History and Rollback" button exists too, but with auto-sync on, Git is the source of truth.)

Bonus: change `GREETING` in `deploy/base/kustomization.yaml` and push. The ConfigMap gets a new hashed
name and the API pods restart with the new message, without rebuilding any image.

---

## 6. Troubleshooting

| Symptom | Check | Usual fix |
|---|---|---|
| Anything weird | `kubectl config current-context` | Must be `kind-argocd-lab` (`kubectl config use-context kind-argocd-lab`) |
| `Unable to connect to the server` | Is Docker Desktop running? `docker ps` shows `argocd-lab-control-plane`? | Start Docker Desktop; `docker start argocd-lab-control-plane`; wait ~1 min |
| Pods `ErrImagePull` / `ImagePullBackOff` | `kubectl -n hello-app describe pod <name>` | Tag in overlay was not loaded: run `.\.tools\kind.exe load docker-image hello-api:<tag> hello-web:<tag> --name argocd-lab`, or fix the tag |
| App shows `OutOfSync` for a long time | Was the change pushed? `git status`, `git log origin/main -1` | `git push`; then refresh annotation (section 4) |
| App `Unknown` / `ComparisonError` | UI → app → error message; `kubectl -n argocd logs deploy/argocd-repo-server --tail=50` | Repo URL/branch/path typo, or repo is private without credentials |
| Pods `CrashLoopBackOff` | `kubectl -n hello-app logs <pod> --previous` | Bug in the app or missing config |
| Pods not Ready | `kubectl -n hello-app describe pod <pod>` → probe failures in Events | Probe path/port wrong, or app slow to start |
| `localhost:9080` doesn't load | Is the port-forward window still running? | Re-run it. Port-forwards end when pods restart or the window closes |
| `bind: address already in use` on port-forward | `Get-NetTCPConnection -LocalPort 9080 -State Listen` | Pick another local port, e.g. `9180:8080` |
| Forgot Argo CD password | | Re-run the command in Step 3 (works until you delete that secret) |
| Kind cluster won't start, "cgroup v1" errors | `docker info --format '{{.CgroupVersion}}'` | Stay on Kubernetes ≤1.34 with this Docker Desktop, or upgrade Docker Desktop |

Handy commands:

```powershell
kubectl -n argocd get applications
kubectl -n argocd describe application hello-app      # sync result, conditions, events
kubectl -n hello-app get all
kubectl -n hello-app get events --sort-by=.lastTimestamp
docker exec argocd-lab-control-plane crictl images | Select-String hello   # images loaded into kind
```

---

## 7. After a computer restart

| Thing | Survives restart? | Why / what to do |
|---|---|---|
| Git repo on GitHub, your local files | ✅ | |
| kind cluster (Argo CD, your app, its config) | ✅ usually | It's one Docker container (`argocd-lab-control-plane`) with all state inside. Docker restarts it when Docker Desktop starts. If not: `docker start argocd-lab-control-plane` |
| Images loaded with `kind load` | ✅ | Stored inside the node container |
| kubeconfig context `kind-argocd-lab` | ✅ | But the *current* context may be something else; check it (Step 0) |
| Argo CD admin password | ✅ | Same secret |
| **Port-forwards** (`9443`, `9080`, `9081`) | ❌ | Re-run them. They are just processes in your terminal windows |
| Docker Desktop itself | depends | Start it (or enable "Start Docker Desktop when you sign in") |

After a restart: start Docker Desktop → wait until `kubectl get nodes` shows Ready (1–2 min) →
start port-forwards. Argo CD resumes syncing by itself.

---

## 8. Cleanup: three different levels

**A. Delete just the application** (cluster and Argo CD stay; you can re-create it any time):

```powershell
kubectl delete -f argocd/hello-app.yaml
```

The Application has the `resources-finalizer.argocd.argoproj.io` finalizer, so Argo CD first deletes
everything it deployed (Deployments, Services, ConfigMaps, the `hello-app` namespace), then the Application.
Don't just `kubectl delete namespace hello-app`: with self-heal on, Argo CD would recreate it.
Re-create with `kubectl apply -f argocd/hello-app.yaml`.

**B. Remove Argo CD only** (keeps the cluster):

```powershell
kubectl delete -f argocd/hello-app.yaml            # first, so the app is cleaned up properly
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.4/manifests/install.yaml
kubectl delete namespace argocd
```

**C. Delete the entire local cluster** (Argo CD, the app, loaded images: all gone; frees RAM/disk):

```powershell
.\.tools\kind.exe delete cluster --name argocd-lab
```

This removes only `argocd-lab`. Your other clusters (`kind-cch`, `docker-desktop`) are not touched.
It does **not** delete the GitHub repo or your local files. To start over, go back to Step 1.

Optional extras:

```powershell
docker image ls "hello-*"                          # images in Docker Desktop
docker image rm hello-api:<tag> hello-web:<tag>
gh repo delete skmunichetty/argocd-local-lab        # deletes the GitHub repo. Irreversible!
```

---

## 9. Next steps

- GitHub Actions: build images, push to a registry (e.g. GHCR), and commit the new tag automatically.
- Install the `argocd` CLI and try `argocd app diff`, `argocd app history`.
- Add a second overlay (e.g. `overlays/staging`) and a second Application.
- Upgrade Docker Desktop (cgroup v2) and move the kind node to Kubernetes 1.35+.
