# Operations Runbook — BatchOps Dashboard

This is the practical runbook for starting, verifying, deploying, troubleshooting and rolling back the BatchOps Dashboard.

## 1. Environment

The project uses two AWS EC2 instances:

```text
EC2 #1 — Jenkins Server
EC2 #2 — Kubernetes Server
```

Jenkins does not run a Kubernetes cluster. It uses `kubectl` and Kubernetes credentials to communicate with the remote Kubernetes API server.

## 2. Start the Environment

Start both EC2 instances.

Then confirm their current IP addresses.

On Kubernetes:

```bash
hostname -I
```

On Jenkins:

```bash
hostname -I
```

If instances were stopped and started, do not assume the old private IP is still valid unless your AWS configuration preserves it.

## 3. Verify Kubernetes

On the Kubernetes EC2:

```bash
kubectl get nodes
```

Expected:

```text
STATUS: Ready
```

Then:

```bash
kubectl get pods -A
```

Important system components should be running:

```text
kube-apiserver
etcd
kube-controller-manager
kube-scheduler
kube-proxy
coredns
kube-flannel
```

## 4. Check the Application

```bash
kubectl get deployment batchops-dashboard
```

Then:

```bash
kubectl get pods -l app=batchops-dashboard -o wide
```

Expected:

```text
READY   STATUS
1/1     Running
```

## 5. Check the Service

```bash
kubectl get service batchops-dashboard-service
```

Expected mapping:

```text
NodePort:     30001
Service Port: 5000
Target Port:  5000
```

## 6. Check the Currently Deployed Image

```bash
kubectl get deployment batchops-dashboard   -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Example:

```text
lakshmanagowda/batchops-dashboard:build-24
```

## 7. Test the Health Endpoint

The application exposes `/health`.

From the Kubernetes server, where applicable:

```bash
curl -i http://localhost:5000/health
```

Expected:

```text
HTTP/1.1 200 OK
```

with:

```json
{"status":"healthy"}
```

## 8. Test from Browser

Open:

```text
http://<KUBERNETES-EC2-PUBLIC-IP>:30001
```

The request path is:

```text
Browser
  ↓
EC2 :30001
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
```

## 9. Check Health Probes

Find the Pod:

```bash
kubectl get pods -l app=batchops-dashboard
```

Then:

```bash
kubectl describe pod <pod-name>
```

Look for:

```text
Liveness:
Readiness:
```

Expected paths:

```text
/health
```

The Pod should eventually show:

```text
Ready: True
```

## 10. Check Pod Events

```bash
kubectl describe pod <pod-name>
```

Check the bottom of the output under:

```text
Events:
```

Useful for:

- failed probes
- image pull errors
- container restarts
- scheduling issues
- mount problems
- networking problems

## 11. Check Application Logs

```bash
kubectl logs <pod-name>
```

For a restarted container:

```bash
kubectl logs <pod-name> --previous
```

## 12. Check Restarts

```bash
kubectl get pods -l app=batchops-dashboard
```

Watch the:

```text
RESTARTS
```

column.

Increasing restarts can indicate application crashes, liveness failures or other container problems.

## 13. Verify Jenkins

On the Jenkins EC2:

```bash
sudo systemctl status jenkins
```

Check Docker:

```bash
sudo systemctl status docker
```

Check kubectl:

```bash
kubectl version --client
```

## 14. Verify Jenkins → Kubernetes Connectivity

From Jenkins:

```bash
nc -vz <KUBERNETES-PRIVATE-IP> 6443
```

Expected:

```text
Connection ... 6443 ... succeeded!
```

If this fails, check:

1. Kubernetes EC2 is running.
2. kube-apiserver is running.
3. Security Group allows TCP 6443 from Jenkins.
4. Jenkins has the correct Kubernetes private IP.
5. AWS networking is available.

## 15. Check Kubernetes API Server

On Kubernetes:

```bash
sudo ss -lntp | grep 6443
```

Expected:

```text
LISTEN ... :6443 ... kube-apiserver
```

## 16. Verify Jenkins Kubernetes Context

On Jenkins:

```bash
sudo -u jenkins kubectl config view --minify --raw   --output=jsonpath='{.clusters[0].name}{"\n"}{.contexts[0].name}{"\n"}{.users[0].name}{"\n"}'
```

Expected:

```text
batchops-k8s
batchops-k8s
jenkins-deployer
```

Check the API endpoint:

```bash
sudo -u jenkins kubectl config view --minify --raw   --output=jsonpath='{.clusters[0].cluster.server}{"\n"}'
```

Expected format:

```text
https://<KUBERNETES-PRIVATE-IP>:6443
```

## 17. Verify Jenkins Can Access Kubernetes

```bash
sudo -u jenkins kubectl get pods
```

and:

```bash
sudo -u jenkins kubectl get deployment batchops-dashboard
```

## 18. Verify Jenkins RBAC

From Kubernetes:

```bash
kubectl auth can-i patch deployments   --as=system:serviceaccount:default:jenkins-deployer
```

Expected:

```text
yes
```

Check Pods:

```bash
kubectl auth can-i get pods   --as=system:serviceaccount:default:jenkins-deployer
```

Check Services:

```bash
kubectl auth can-i get services   --as=system:serviceaccount:default:jenkins-deployer
```

Check Service creation:

```bash
kubectl auth can-i create services   --as=system:serviceaccount:default:jenkins-deployer
```

The Jenkins account should not have unnecessary cluster-wide permissions. For example:

```bash
kubectl auth can-i list nodes   --as=system:serviceaccount:default:jenkins-deployer
```

is expected to return:

```text
no
```

## 19. Normal Deployment Flow

```text
Developer
   ↓ git push
GitHub
   ↓
Jenkins
   ├── Terraform
   ├── Docker Build
   ├── Docker Push
   ├── Update image tag
   ├── kubectl apply
   └── rollout status
          ↓
     Kubernetes
```

## 20. Trigger a Deployment

From the development machine:

```bash
git status
git add .
git commit -m "Update application"
git push origin main
```

GitHub triggers Jenkins.

Jenkins checks out the new commit and executes the Jenkinsfile.

## 21. Jenkins Pipeline Stages

The pipeline follows:

```text
Checkout
   ↓
Terraform Init
   ↓
Terraform Validate
   ↓
Terraform Plan
   ↓
Build Docker Image
   ↓
Push Docker Image
   ↓
Deploy to Kubernetes
```

## 22. Docker Build Versioning

Jenkins uses `BUILD_NUMBER`.

Example:

```text
Jenkins Build 24
        ↓
lakshmanagowda/batchops-dashboard:build-24
```

Build 25 becomes:

```text
lakshmanagowda/batchops-dashboard:build-25
```

## 23. Kubernetes Deployment Stage

Jenkins:

1. Selects the current image version.
2. Updates `k8s/deployment.yaml` in its workspace.
3. Applies `k8s/deployment.yaml`.
4. Applies `k8s/service.yaml`.
5. Waits for rollout.
6. Displays Deployment, Pod and Service status.

The manifest files come from the GitHub checkout.

The dynamically substituted image tag is not automatically committed back to GitHub.

## 24. Verify a Successful Pipeline

After Jenkins reports:

```text
Finished: SUCCESS
```

run:

```bash
kubectl get deployment batchops-dashboard
```

```bash
kubectl get pods -l app=batchops-dashboard -o wide
```

```bash
kubectl get service batchops-dashboard-service
```

Then:

```bash
kubectl get deployment batchops-dashboard   -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

## 25. Verify Rollout

```bash
kubectl rollout status deployment/batchops-dashboard
```

Expected:

```text
deployment "batchops-dashboard" successfully rolled out
```

## 26. Rollout History

```bash
kubectl rollout history deployment/batchops-dashboard
```

This shows the Deployment revisions.

## 27. Rollback

If the newly deployed version is broken:

```bash
kubectl rollout undo deployment/batchops-dashboard
```

Then:

```bash
kubectl rollout status deployment/batchops-dashboard
```

Verify the image:

```bash
kubectl get deployment batchops-dashboard   -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Then:

```bash
kubectl get pods -l app=batchops-dashboard
```

Finally test the application.

## 28. Rollback to a Specific Revision

First:

```bash
kubectl rollout history deployment/batchops-dashboard
```

Then:

```bash
kubectl rollout undo deployment/batchops-dashboard --to-revision=<REVISION>
```

Verify:

```bash
kubectl rollout status deployment/batchops-dashboard
```

## 29. Troubleshooting — Pod Not Ready

Run:

```bash
kubectl get pods -l app=batchops-dashboard
```

If you see:

```text
0/1 Running
```

inspect:

```bash
kubectl describe pod <pod-name>
```

Look for:

```text
Readiness probe failed
```

If the error is:

```text
HTTP probe failed with statuscode: 404
```

verify that the currently deployed image contains `/health`.

## 30. Troubleshooting — Liveness Failure

Run:

```bash
kubectl describe pod <pod-name>
```

Look for:

```text
Liveness probe failed
```

Then:

```bash
kubectl logs <pod-name>
```

Verify `/health` returns HTTP 200.

## 31. Troubleshooting — Image Pull Failure

Check:

```bash
kubectl describe pod <pod-name>
```

Look for:

```text
ImagePullBackOff
ErrImagePull
```

Check:

1. Image name
2. Image tag
3. Docker Hub availability
4. Image access/visibility
5. Kubernetes node network connectivity

Verify:

```bash
kubectl get deployment batchops-dashboard   -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

## 32. Troubleshooting — Jenkins Cannot Reach Kubernetes

From Jenkins:

```bash
nc -vz <KUBERNETES-PRIVATE-IP> 6443
```

If it fails, on Kubernetes:

```bash
sudo ss -lntp | grep 6443
```

Then check:

- Kubernetes server is running
- kube-apiserver is running
- Security Group allows TCP 6443
- Jenkins uses the correct private IP
- AWS network connectivity is available

## 33. Troubleshooting — RBAC Forbidden

Example:

```text
User "system:serviceaccount:default:jenkins-deployer"
cannot get resource "services"
```

Check:

```bash
kubectl auth can-i get services   --as=system:serviceaccount:default:jenkins-deployer
```

If it returns `no`, review:

```text
k8s/jenkins-rbac.yaml
```

Apply the updated RBAC from Kubernetes:

```bash
kubectl apply -f k8s/jenkins-rbac.yaml
```

Then verify again.

## 34. Troubleshooting — Docker Hub Credential Failure

If Jenkins reports:

```text
Could not find credentials entry with ID 'dockerhub-credentials'
```

check:

```text
Jenkins
  → Manage Jenkins
  → Credentials
  → Global credentials
```

Verify that the credential ID exactly matches the Jenkinsfile.

Never put Docker Hub passwords directly in the Jenkinsfile.

## 35. Troubleshooting — Service

Check:

```bash
kubectl get service batchops-dashboard-service
```

Then:

```bash
kubectl describe service batchops-dashboard-service
```

Confirm the Service selector:

```text
app=batchops-dashboard
```

matches the Pod label.

Also confirm the application listens on port `5000`.

## 36. Troubleshooting — NodePort

If the application works internally but not from the browser:

```bash
kubectl get service batchops-dashboard-service
```

Confirm:

```text
30001:5000
```

Then check the Kubernetes EC2 Security Group allows the NodePort traffic.

Test:

```text
http://<KUBERNETES-EC2-PUBLIC-IP>:30001
```

## 37. Important Ports

| Port | Purpose |
|------|---------|
| 22 | SSH |
| 6443 | Kubernetes API — Jenkins → Kubernetes |
| 30001 | NodePort — User → Application |
| 5000 | Flask — Service → Container |

Remember:

```text
6443 = Kubernetes management
30001 = external application access
5000 = application port
```

## 38. Verify Kubernetes API Certificate

```bash
sudo openssl x509   -in /etc/kubernetes/pki/apiserver.crt   -noout   -subject   -ext subjectAltName
```

The Kubernetes server private IP should be present in the Subject Alternative Name list.

## 39. Verify Jenkins Token Without Printing It

```bash
sudo -u jenkins kubectl config view --minify --raw   --output=jsonpath='{.users[0].user.token}' | wc -c
```

Do not print or share the actual token.

## 40. Verify Manifest Files on Jenkins

Jenkins checks out the repository into:

```text
/var/lib/jenkins/workspace/BatchOps-CI/
```

Manifests are:

```text
/var/lib/jenkins/workspace/BatchOps-CI/k8s/deployment.yaml
/var/lib/jenkins/workspace/BatchOps-CI/k8s/service.yaml
/var/lib/jenkins/workspace/BatchOps-CI/k8s/jenkins-rbac.yaml
```

## 41. Git Source of Truth

GitHub is the source-controlled copy.

The Kubernetes EC2 does not need to maintain a permanent Git checkout for Jenkins deployments.

The flow is:

```text
GitHub
   ↓
Jenkins checkout
   ↓
Update image tag in workspace
   ↓
kubectl apply
   ↓
Kubernetes API
```

Avoid manually editing the Jenkins workspace. Permanent changes should be made in Git, committed and pushed.

## 42. Stopping the Project

When finished for the day:

### Kubernetes

```bash
kubectl get nodes
kubectl get pods -A
kubectl get deployment
kubectl get service
```

### Jenkins

Ensure no important pipeline is running.

Then stop both EC2 instances from AWS.

## 43. Restarting Later

When returning:

```text
1. Start Kubernetes EC2
2. Start Jenkins EC2
3. Check Kubernetes node
4. Check Kubernetes Pods
5. Check Jenkins
6. Check Jenkins → Kubernetes :6443
7. Check kubectl context
8. Test application
9. Run pipeline if required
```

Start with:

```bash
kubectl get nodes
```

Then:

```bash
kubectl get pods -A
```

Then:

```bash
kubectl get deployment batchops-dashboard
```

Then:

```bash
kubectl get service batchops-dashboard-service
```

## 44. Quick Health Checklist

```text
[ ] Kubernetes EC2 running
[ ] Jenkins EC2 running
[ ] Kubernetes node Ready
[ ] kube-apiserver running
[ ] CoreDNS running
[ ] Flannel running
[ ] Application Pod Running
[ ] Application Pod Ready
[ ] Deployment Available
[ ] Service exists
[ ] NodePort 30001 available
[ ] /health returns HTTP 200
[ ] Browser can access application
[ ] Jenkins can reach Kubernetes :6443
[ ] Jenkins kubectl context is correct
[ ] Jenkins RBAC permissions are correct
```

## 45. Emergency Rollback Checklist

```bash
# 1. Current image
kubectl get deployment batchops-dashboard   -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

# 2. Deployment history
kubectl rollout history deployment/batchops-dashboard

# 3. Roll back
kubectl rollout undo deployment/batchops-dashboard

# 4. Wait
kubectl rollout status deployment/batchops-dashboard

# 5. Check Pods
kubectl get pods -l app=batchops-dashboard

# 6. Check image
kubectl get deployment batchops-dashboard   -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

# 7. Health
curl -i http://localhost:5000/health

# 8. Browser
# http://<KUBERNETES-EC2-PUBLIC-IP>:30001
```

## 46. Key Operational Lessons

### Jenkins does not need a Kubernetes cluster

It needs:

```text
kubectl
+
Kubernetes credentials
+
network access to API server :6443
```

### kubectl runs on Jenkins, but the workload runs on Kubernetes

```text
Jenkins
  |
  | kubectl
  v
Kubernetes API
  |
  v
Deployment
  |
  v
Pod
```

### Build number identifies the artifact

```text
Jenkins build-24
        ↓
Docker build-24
        ↓
Kubernetes build-24
```

### Readiness vs Liveness

```text
Readiness = Should this Pod receive traffic?
Liveness  = Is this application still alive?
```

### Rollback

```text
Current revision
      ↓
kubectl rollout undo
      ↓
Previous revision
```

## 47. Monitoring Scope

Prometheus and Grafana are intentionally not installed as part of this project. Monitoring was covered separately during the DevOps learning phase.

This project focuses on:

```text
CI/CD
Infrastructure as Code
Docker
Kubernetes
Networking
RBAC
Health Checks
Rolling Deployment
Rollback
```

## 48. Frequently Used Commands

```bash
kubectl get nodes

kubectl get pods -A

kubectl get pods -l app=batchops-dashboard -o wide

kubectl get deployment batchops-dashboard

kubectl get service batchops-dashboard-service

kubectl get deployment batchops-dashboard   -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

kubectl rollout status deployment/batchops-dashboard

kubectl rollout history deployment/batchops-dashboard

kubectl rollout undo deployment/batchops-dashboard

kubectl describe pod <pod-name>

kubectl logs <pod-name>

kubectl auth can-i get services   --as=system:serviceaccount:default:jenkins-deployer

kubectl auth can-i patch deployments   --as=system:serviceaccount:default:jenkins-deployer
```
