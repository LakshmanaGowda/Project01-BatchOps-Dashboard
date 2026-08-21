# Architecture — BatchOps Dashboard

## 1. Purpose

This document describes the technical architecture of the BatchOps Dashboard project, with focus on the two-EC2 design, Jenkins-to-Kubernetes communication, Docker image flow, Kubernetes deployment, networking, health checks, rolling updates, and rollback.

## 2. High-Level Architecture

```text
                               ┌─────────────────────┐
                               │       GitHub        │
                               │ Project Repository  │
                               └──────────┬──────────┘
                                          │ Git Push
                                          ▼
                         ┌────────────────────────────────┐
                         │         Jenkins EC2            │
                         │ Jenkins / Git / Terraform      │
                         │ Docker / kubectl / CI/CD       │
                         └───────────────┬────────────────┘
                                         │
                    ┌────────────────────┼────────────────────┐
                    │                    │                    │
                    ▼                    ▼                    ▼
               Terraform            Docker Build          kubectl
                                         │                    │
                                         ▼                    │
                                    Docker Hub                │
                                         │                    │
                                         │ Image Pull         │
                                         ▼                    │
                            ┌────────────────────────────┐   │
                            │      Kubernetes EC2        │   │
                            │                            │   │
                            │ kube-apiserver :6443      │◄──┘
                            │ etcd / scheduler           │
                            │ controller-manager         │
                            │ kubelet / containerd       │
                            │ Flannel                    │
                            │                            │
                            │ Deployment → ReplicaSet    │
                            │             → Pod           │
                            │             → Container     │
                            └────────────┬───────────────┘
                                         │
                                         │ NodePort :30001
                                         ▼
                                  ┌──────────────┐
                                  │ User Browser │
                                  └──────────────┘
```

## 3. Two-EC2 Design

### EC2 #1 — Jenkins Server

Responsible for:

- Jenkins
- Git checkout
- Terraform
- Docker image creation
- Docker Hub publishing
- kubectl
- Communicating with the Kubernetes API server

Jenkins does **not** run the application Pod.

### EC2 #2 — Kubernetes Server

Responsible for:

- Kubernetes control plane
- kube-apiserver
- etcd
- kube-scheduler
- kube-controller-manager
- kubelet
- containerd
- Flannel networking
- Deployment, ReplicaSet and Pods
- Application container

The BatchOps Dashboard application runs on this EC2.

## 4. Why They Are Separate

```text
Jenkins EC2
    |
    | HTTPS :6443
    v
Kubernetes API Server
    |
    v
Deployment → ReplicaSet → Pod → Container
```

Jenkins does not need a Kubernetes cluster of its own. It needs `kubectl`, credentials, and network access to the remote Kubernetes API.

> Jenkins executes `kubectl`, but Kubernetes performs the actual deployment.

## 5. Jenkins → Kubernetes Communication

The Kubernetes API server listens on TCP `6443`.

```text
Jenkins EC2
    |
    | HTTPS / TCP 6443
    v
Kubernetes EC2
    |
    v
kube-apiserver
```

Connectivity was verified from Jenkins with:

```bash
nc -vz <KUBERNETES-PRIVATE-IP> 6443
```

The Kubernetes API server certificate includes the Kubernetes EC2 private IP as a valid Subject Alternative Name.

## 6. Jenkins Kubernetes Authentication

Jenkins uses the dedicated ServiceAccount:

```text
jenkins-deployer
```

defined in:

```text
k8s/jenkins-rbac.yaml
```

The Role provides the permissions required by the application deployment.

Deployment permissions:

```text
get, list, watch, patch, update
```

Pod permissions:

```text
get, list, watch
```

Service permissions:

```text
get, list, watch, create, update, patch
```

The account does not have unrestricted cluster-admin access. For example, it cannot list cluster nodes. This follows the principle of least privilege.

## 7. Source-Controlled Kubernetes Manifests

The repository contains:

```text
k8s/
├── deployment.yaml
├── service.yaml
└── jenkins-rbac.yaml
```

Jenkins checks out these files into its workspace.

During deployment, Jenkins updates the image tag in its workspace and applies the manifests with `kubectl`.

The dynamically modified image tag is not automatically committed back to GitHub.

## 8. CI/CD Flow

```text
GitHub
   ↓
Jenkins
   ├── Terraform Init
   ├── Terraform Validate
   ├── Terraform Plan
   ├── Docker Build
   ├── Docker Push
   ├── Update deployment.yaml image
   ├── kubectl apply
   └── Rollout Status
             ↓
       Kubernetes
```

## 9. Terraform

Jenkins runs:

```bash
terraform init -input=false
terraform validate
terraform plan -input=false
```

Terraform uses an S3 backend for state management and verifies that the AWS infrastructure matches the configuration.

## 10. Docker Image Flow

Jenkins builds a versioned image:

```text
lakshmanagowda/batchops-dashboard:build-24
```

and pushes it to Docker Hub:

```text
Jenkins EC2
    |
    | docker push
    v
Docker Hub
    |
    | image pull
    v
Kubernetes Pod
```

## 11. Why Build Numbers Are Used

Images use tags such as:

```text
build-24
build-25
build-26
```

instead of relying only on `latest`.

This makes each CI artifact identifiable and supports Kubernetes Deployment revision history and rollback.

## 12. Kubernetes Deployment Hierarchy

```text
Deployment
     ↓
ReplicaSet
     ↓
Pod
     ↓
Container
     ↓
Flask Application
```

The project currently uses:

```yaml
replicas: 1
```

## 13. Kubernetes Components

The single-node cluster includes components such as:

```text
kube-apiserver
etcd
kube-scheduler
kube-controller-manager
kubelet
containerd
kube-proxy
Flannel
CoreDNS
```

The application workload runs on the same Kubernetes EC2 because this is a single-node cluster.

## 14. Application Container

The application image follows:

```text
lakshmanagowda/batchops-dashboard:build-<BUILD_NUMBER>
```

The Flask application listens on port `5000` and starts with:

```python
app.run(
    host="0.0.0.0",
    port=5000
)
```

## 15. Kubernetes Service

The application is exposed using:

```text
Service: batchops-dashboard-service
Type: NodePort
NodePort: 30001
Service Port: 5000
Target Port: 5000
```

The Service selects Pods using:

```text
app=batchops-dashboard
```

## 16. Complete User Traffic Flow

A user accesses:

```text
http://<KUBERNETES-EC2-PUBLIC-IP>:30001
```

Traffic follows:

```text
User Browser
     |
     | HTTP :30001
     v
Kubernetes EC2
     |
     v
NodePort
     |
     v
Kubernetes Service
     |
     | targetPort 5000
     v
BatchOps Dashboard Pod
     |
     v
Container
     |
     | :5000
     v
Flask Application
     |
     v
jobs.json
     |
     v
HTML Dashboard
```

## 17. Detailed Request Path

1. The browser connects to the Kubernetes EC2 on NodePort `30001`.
2. Kubernetes receives the request through the NodePort.
3. `batchops-dashboard-service` selects the Pod using `app=batchops-dashboard`.
4. The Service forwards traffic to target port `5000`.
5. The request reaches the Pod and its container.
6. Flask processes `/`.
7. Flask reads `jobs.json` and renders `templates/index.html`.
8. The response travels back to the browser.

## 18. Runtime Traffic Diagram

```text
┌──────────────┐
│ User Browser │
└──────┬───────┘
       │ HTTP :30001
       ▼
┌─────────────────────────┐
│ Kubernetes EC2          │
│ NodePort :30001         │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Kubernetes Service      │
│ batchops-dashboard      │
│ :5000                   │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Application Pod         │
│ 10.244.x.x              │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Container / Flask :5000 │
└─────────────────────────┘
```

## 19. Kubernetes Networking

Flannel provides the Pod network. Pods receive internal addresses such as:

```text
10.244.x.x
```

Simplified path:

```text
NodePort
    ↓
Service
    ↓
Pod Network
    ↓
Pod IP
    ↓
Container Port 5000
```

## 20. Health Checks

The Flask application exposes:

```text
/health
```

and returns:

```json
{
  "status": "healthy"
}
```

### Readiness Probe

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 5000
  initialDelaySeconds: 5
  periodSeconds: 5
```

Readiness determines whether the Pod is considered ready to receive traffic.

### Liveness Probe

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 5000
  initialDelaySeconds: 10
  periodSeconds: 10
```

Liveness determines whether the application is still alive. Repeated liveness failures can cause the container to be restarted.

## 21. Rolling Deployment

A new image, for example:

```text
build-24 → build-25
```

causes Kubernetes to perform a rolling update.

```text
Old Pod: build-24
       ↓
New Pod: build-25
       ↓
Readiness succeeds
       ↓
New Pod becomes Ready
       ↓
Old Pod terminates
```

Jenkins waits using:

```bash
kubectl rollout status deployment/batchops-dashboard --timeout=120s
```

## 22. Rollback

Rollback is performed with:

```bash
kubectl rollout undo deployment/batchops-dashboard
```

During the project, a real rollback restored the previous Deployment revision, changing the application from `build-24` back to `build-23`.

Rollback restores the previous Kubernetes Deployment revision; it does not rebuild the old application.

## 23. Port Summary

| Port | Purpose |
|------|---------|
| 22 | SSH |
| 5000 | Flask application / target port |
| 30001 | Kubernetes NodePort |
| 6443 | Kubernetes API server |

```text
Jenkins → Kubernetes: 6443
User → Application: 30001
Service → Flask: 5000
```

## 24. Architecture Summary

### CI/CD Flow

```text
GitHub
   ↓
Jenkins EC2
   ↓
Terraform
   ↓
Docker Build
   ↓
Docker Hub
   ↓
kubectl
   ↓
Kubernetes API :6443
   ↓
Deployment
   ↓
Pod
   ↓
Container
```

### Application Flow

```text
User
   ↓
Kubernetes EC2 :30001
   ↓
NodePort
   ↓
Service
   ↓
Pod
   ↓
Container :5000
   ↓
Flask
   ↓
Dashboard
```

## 25. Scope

Prometheus and Grafana are intentionally outside the scope of this project. Monitoring was covered separately during the DevOps learning phase.

This project focuses on:

```text
CI/CD
Infrastructure as Code
Containerization
Kubernetes
Networking
RBAC
Health Checks
Rolling Updates
Rollback
```
