# PowerShell script to automate registry setup and installation

# Function to read user input with prompt
function Read-UserInput {
    param([string]$prompt)
    Write-Host $prompt -NoNewline
    return (Read-Host)
}

function Sanitize-Name {
    param([string]$name)
    # Convert to lowercase
    $name = $name.ToLower()
    # Replace any character that's not a-z, 0-9, '-', or '.' with '-'
    $name = $name -replace '[^a-z0-9\-\.]', '-'
    # Ensure it starts and ends with an alphanumeric character
    $name = $name -replace '^[^a-z0-9]+', ''
    $name = $name -replace '[^a-z0-9]+$', ''
    # Truncate to 53 characters if necessary
    if ($name.Length -gt 53) {
        $name = $name.Substring(0, 53)
    }
    return $name
}

# Ask user for registry name
$registryName = Read-UserInput "Enter the name of the registry: "
$registryName = Sanitize-Name $registryName

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

# Create the Docker registry deployment YAML content
$registryDeployment = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: registry
  namespace: $namespace
  labels:
    app: registry
spec:
  replicas: 1
  selector:
    matchLabels:
      app: registry
  template:
    metadata:
      labels:
        app: registry
    spec:
      containers:
      - name: registry
        image: registry:2
        ports:
        - containerPort: 80
          name: registry
        env:
        - name: REGISTRY_HTTP_ADDR
          value: "0.0.0.0:80"
"@

# Create the service YAML content
$service = @"
apiVersion: v1
kind: Service
metadata:
  name: container-registry-public
  namespace: $namespace
spec:
  selector:
    app: registry
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
"@

# Create the ingress service YAML content
$ingressService = @"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: container-registry-ingress
  namespace: $namespace
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: 5g
spec:
  ingressClassName: nginx
  rules:
  - host: $domain
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: container-registry-public
            port:
              number: 80
"@

# Write the registry namespace YAML to file
$registryNamespaceFilePath = "registry-namespace.yaml"
Set-Content -Path $registryNamespaceFilePath -Value $registryNamespace -Encoding UTF8

# Write the registry deployment YAML to file
$registryDeploymentFilePath = "registry-deployment.yaml"
Set-Content -Path $registryDeploymentFilePath -Value $registryDeployment -Encoding UTF8

# Write the service YAML to file
$serviceFilePath = "service.yaml"
Set-Content -Path $serviceFilePath -Value $service -Encoding UTF8

# Write the ingress service YAML to file
$ingressServiceFilePath = "ingress-service.yaml"
Set-Content -Path $ingressServiceFilePath -Value $ingressService -Encoding UTF8

# Delete the namespace if it currently exists
kubectl delete namespace $namespace -n $namespace

# Confirm namespace has been deleted
Write-Host "Namespace deleted successfully" 

# Apply registry namespace
kubectl apply -f $registryNamespaceFilePath

# Apply the registry deployment
kubectl apply -f $registryDeploymentFilePath

# Create the service
kubectl apply -f $serviceFilePath

# Apply ingress 
kubectl apply -f $ingressServiceFilePath

# Notify user of successful installation
Write-Host "Registry installed successfully"
