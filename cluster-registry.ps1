# PowerShell script to automate registry setup and installation

function Generate-ValuesYaml {
    param(
        [string]$registryName,
        [string]$storageType,
        [string]$storagePath,
        [string]$storageNodepool
    )
    $valuesYaml = @"
service:
  enabled: false
labels:
  app: docker-registry
  app.kubernetes.io/name: docker-registry
  app.kubernetes.io/instance: $registryName
  app.kubernetes.io/version: "2.8.1"
  app.kubernetes.io/component: registry
  app.kubernetes.io/part-of: container-infrastructure
  app.kubernetes.io/managed-by: helm
  environment: development
  team: devops
"@

    if ($storageType -eq "nodepool") {
        $valuesYaml += @"

persistence:
  enabled: true
  storageClass: ""
  accessMode: ReadWriteOnce
  size: 100Gi
  volumes:
    - name: data
      hostPath:
        path: $storagePath
        type: DirectoryOrCreate
nodeSelector:
  agentpool: $storageNodepool
"@
    }
    elseif ($storageType -eq "managed-disk") {
        $valuesYaml += @"

persistence:
  enabled: true
  storageClass: managed-premium
  accessMode: ReadWriteOnce
  size: 100Gi
"@
    }

    return $valuesYaml
}

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

# Ask user for storage type
$storageType = Read-UserInput "Enter storage type (nodepool/managed-disk): "

$storagePath = ""
$storageNodepool = ""

if ($storageType -eq "nodepool") {
    $storagePath = Read-UserInput "Enter the storage path on the nodes (e.g., /mnt/registry-data): "
    $storageNodepool = Read-UserInput "Enter the name of the storage nodepool: "
}

# Define namespace for private domains
$namespace = "container-registry"

# Create the registry namespace YAML content
$registryNamespace = @"
apiVersion: v1
kind: Namespace
metadata:
    name: $namespace
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
    app: docker-registry
  ports:
  - protocol: TCP
    port: 5000
    targetPort: 5000
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
              number: 5000
"@

# Write the service to a file
$serviceFilePath = "service.yaml"
Set-Content -Path $serviceFilePath -Value $service -Encoding UTF8

# Write registry namespace YAML to file
$registryNamespaceFilePath = "registry-namespace.yaml"
Set-Content -Path $registryNamespaceFilePath -Value $registryNamespace -Encoding UTF8

# Write ingress service YAML to file
$ingressServiceFilePath = "ingress-service.yaml"
Set-Content -Path $ingressServiceFilePath -Value $ingressService -Encoding UTF8

# delete the namespace if it currently exists
kubectl delete namespace $namespace

# confirm namespace has been deleted
Write-Host "Namespace deleted successfully" 

# Add Helm stable repository
helm repo add stable https://charts.helm.sh/stable

# Update Helm repositories
helm repo update

# Apply registry namespace
kubectl apply -f $registryNamespaceFilePath

# Generate values.yaml content
$valuesYamlContent = Generate-ValuesYaml -registryName $registryName -storageType $storageType -storagePath $storagePath -storageNodepool $storageNodepool

# Write values.yaml to file
$valuesYamlPath = "values.yaml"
Set-Content -Path $valuesYamlPath -Value $valuesYamlContent -Encoding UTF8

# Update the Helm install command
helm install $registryName stable/docker-registry `
  --namespace $namespace `
  --values $valuesYamlPath

# Create the service
kubectl apply -f $serviceFilePath

# Apply ingress 
kubectl apply -f $ingressServiceFilePath

# Notify user of successful installation
Write-Host "Registry installed successfully"