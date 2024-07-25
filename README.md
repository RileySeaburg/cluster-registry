# Kubernetes Cluster Registry One Click Deploy Script

## How this script works

1. Run this script
2. Enter your desgniated hostname for the registry


## Powershell Script

If you have issues running the rust script, you can use the powershell script instead as cluster-registry.ps1

### How to run the script

```powershell
.\cluster-registry.ps1
```

## Prerequisites
1. Helm
2. Kubernetes Cluster
3. Kubectl installed
4. Kubeconfig file configured

## What does this script do?

1. Collects the registry name
2. Collects the hostname for the registry
3. Creates a namespace called `registry`
4. Creates an ingress service for the registry
5. Adds the helm repo for the registry
6. Updates the helm repo
7. Installs the registry helm chart
8. Responds with a success message

---
# [MIT Licensed](/LICENSE)

