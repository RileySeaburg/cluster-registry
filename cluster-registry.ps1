# PowerShell script to automate registry setup and installation

# Function to read user input with prompt
function Read-UserInput {
    param([string]$prompt)
    Write-Host $prompt -NoNewline
    return (Read-Host)
}

# Ask user for registry name
$registryName = Read-UserInput "Enter the name of the registry: "

# Ask user for domain name
$domain = Read-UserInput "Enter your domain name: "

# Define namespace for private domains
$namespace = "container-registry"

# Create the registry namespace YAML content
$registryNamespace = @"
apiVersion: v1
kind: Namespace
metadata:
    name: $namespace
"@

# Create the ingress service YAML content
$ingressService = @"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: container-registry-ingress
  namespace: $namespace
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/proxy-body-size: 5g
spec:
  rules:
  - host: $domain
    http:
      paths:
      - backend:
          service:
            name: docker-registry-public
            port:
              number: 5000
        path: /
        pathType: Prefix
  tls: []
"@

# Write registry namespace YAML to file
$registryNamespaceFilePath = "registry-namespace.yaml"
Set-Content -Path $registryNamespaceFilePath -Value $registryNamespace -Encoding UTF8

# Write ingress service YAML to file
$ingressServiceFilePath = "ingress-service.yaml"
Set-Content -Path $ingressServiceFilePath -Value $ingressService -Encoding UTF8

# Apply registry namespace
kubectl apply -f $registryNamespaceFilePath

# Apply ingress service
kubectl apply -f $ingressServiceFilePath

# Add Helm stable repository
helm repo add stable https://charts.helm.sh/stable

# Update Helm repositories
helm repo update

# Install the registry using Helm
helm install $registryName stable/docker-registry --namespace $namespace --set podLabels.app=docker-registry

# Notify user of successful installation
Write-Host "Registry installed successfully"
