# Project 01 — BatchOps Dashboard

An end-to-end DevOps project demonstrating the complete lifecycle of a containerized application:

**Source Code → GitHub → Jenkins → Terraform → Docker → Docker Hub → Kubernetes → Running Application**

The project uses two separate AWS EC2 instances:

- **Jenkins EC2** — CI/CD and automation server
- **Kubernetes EC2** — Kubernetes control plane and application runtime

The project demonstrates Docker, Jenkins, Terraform, AWS, Kubernetes, Kubernetes networking, RBAC, health probes, rolling deployments and rollback.

---

# 1. Project Purpose

The purpose of this project is to build a practical DevOps pipeline around a small Flask-based BatchOps Dashboard application.

The application itself is intentionally simple.

The main objective is to demonstrate how an application can move through the following lifecycle:

```text
Developer
    |
    | git push
    v
GitHub
    |
    | webhook / push trigger
    v
Jenkins EC2
    |
    +--> Terraform
    |
    +--> Docker Build
    |
    +--> Docker Push
    |
    +--> kubectl
             |
             | HTTPS :6443
             v
       Kubernetes EC2
             |
             v
        Deployment
             |
             v
         ReplicaSet
             |
             v
            Pod
             |
             v
       Docker Container
             |
             v
       Flask Application