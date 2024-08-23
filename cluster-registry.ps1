# PowerShell script to automate registry setup and installation

function Generate-ValuesYaml {
    param(
        [string]$registryName,
        [string]$nodepoolName
    )
    return @"
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
nodeSelector:
  agentpool: $nodepoolName
tolerations:
- key: "kubernetes.io/pool"
  operator: "Equal"
  value: "$nodepoolName"
  effect: "NoSchedule"
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: agentpool
          operator: In
          values:
          - $nodepoolName
        - key: beta.kubernetes.io/os
          operator: In
          values:
          - linux
persistence:
  enabled: true
  storageClass: nodepool-storage
  accessMode: ReadWriteOnce
  size: 100Gi
"@
}

function Get-NodepoolNames {
    $nodepools = kubectl get nodes -o jsonpath='{.items[*].metadata.labels.agentpool}' | Select-Object -Unique
    return $nodepools -split '\s+'
}

function Read-UserInput {
    param(
        [string]$prompt,
        [string[]]$validOptions = @(),
        [bool]$allowCustom = $false
    )
    while ($true) {
        Write-Host $prompt -NoNewline
        $input = Read-Host
        if ($validOptions.Count -eq 0 -or $allowCustom) {
            return $input
        }
        if ($input -in $validOptions) {
            return $input
        }
        Write-Host "Invalid input. Please choose from the following options: $($validOptions -join ', ')"
    }
}

function Sanitize-Name {
    param([string]$name)
    $name = $name.ToLower()
    $name = $name -replace '[^a-z0-9\-\.]', '-'
    $name = $name -replace '^[^a-z0-9]+', ''
    $name = $name -replace '[^a-z0-9]+$', ''
    if ($name.Length -gt 53) {
        $name = $name.Substring(0, 53)
    }
    return $name
}

function Create-TLSSecret {
    param(
        [string]$namespace,
        [string]$secretName,
        [string]$certFile,
        [string]$keyFile
    )

    if (-not (Test-Path $certFile) -or -not (Test-Path $keyFile)) {
        Write-Host "Certificate files not found. Please ensure registry.crt and registry.key are in the same directory as this script."
        exit 1
    }

    kubectl create secret tls $secretName `
        --cert=$certFile `
        --key=$keyFile `
        --namespace=$namespace
}

function Create-StoragePoolResources {
    param(
        [string]$namespace,
        [string]$nodepoolName,
        [string]$storagePath
    )

    $storageClass = @"
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nodepool-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
"@

    $storageClassPath = "nodepool-storage-class.yaml"
    Set-Content -Path $storageClassPath -Value $storageClass

    kubectl apply -f $storageClassPath

    $nodes = kubectl get nodes -l agentpool=$nodepoolName -o jsonpath='{.items[*].metadata.name}'

    foreach ($node in $nodes.Split()) {
        $persistentVolume = @"
apiVersion: v1
kind: PersistentVolume
metadata:
  name: registry-pv-$node
spec:
  capacity:
    storage: 100Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nodepool-storage
  local:
    path: $storagePath
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $node
"@

        $pvPath = "pv-$node.yaml"
        Set-Content -Path $pvPath -Value $persistentVolume
        kubectl apply -f $pvPath
    }
}


function Create-DirectoryDaemonSet {
    param(
        [string]$namespace,
        [string]$nodepoolName,
        [string]$directoryPath
    )

    $daemonSet = @"
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: registry-directory-creator
  namespace: $namespace
spec:
  selector:
    matchLabels:
      name: registry-directory-creator
  template:
    metadata:
      labels:
        name: registry-directory-creator
    spec:
      nodeSelector:
        agentpool: $nodepoolName
      containers:
      - name: directory-creator
        image: busybox
        command: ["/bin/sh", "-c", "mkdir -p $directoryPath && chmod 777 $directoryPath && sleep infinity"]
        volumeMounts:
        - name: host-mnt
          mountPath: /mnt
      volumes:
      - name: host-mnt
        hostPath:
          path: /mnt
      tolerations:
      - operator: Exists
"@

    $daemonSetPath = "registry-directory-creator-daemonset.yaml"
    Set-Content -Path $daemonSetPath -Value $daemonSet
    kubectl apply -f $daemonSetPath
}

try {

  # Ask user for registry name
  $registryName = Read-UserInput "Enter the name of the registry: "
  $registryName = Sanitize-Name $registryName

  # Ask user for domain name
  $domain = Read-UserInput "Enter your domain name: "

  # Ask for nodepool name and storage path
  $nodepoolName = Read-UserInput "Enter the name of the storage nodepool: "
  $storagePath = Read-UserInput "Enter the path for local storage on the nodes: "

  # Define namespace for private domains
  $namespace = "container-registry"

  # Delete the namespace if it currently exists
  kubectl delete namespace $namespace

  # Wait for namespace deletion to complete
  Write-Host "Waiting for namespace deletion to complete..."
  while (kubectl get namespace $namespace 2>$null) {
      Start-Sleep -Seconds 5
  }

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
  - name: registry
    protocol: TCP
    port: 5000
    targetPort: 5000
  - name: http
    protocol: TCP
    port: 80
    targetPort: 5000
  - name: https
    protocol: TCP
    port: 443
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
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - $domain
    secretName: registry-tls-secret
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

  # Write YAMLs to files
  $registryNamespaceFilePath = "registry-namespace.yaml"
  Set-Content -Path $registryNamespaceFilePath -Value $registryNamespace -Encoding UTF8

  $serviceFilePath = "service.yaml"
  Set-Content -Path $serviceFilePath -Value $service -Encoding UTF8

  $ingressServiceFilePath = "ingress-service.yaml"
  Set-Content -Path $ingressServiceFilePath -Value $ingressService -Encoding UTF8

  # Apply registry namespace
  kubectl apply -f $registryNamespaceFilePath

  # After creating the namespace and before creating PersistentVolumes
  Create-DirectoryDaemonSet -namespace $namespace -nodepoolName $nodepoolName -directoryPath $storagePath

  # Wait for DaemonSet to be ready
  Write-Host "Waiting for DaemonSet to create directories on all nodes..."
  kubectl rollout status daemonset/registry-directory-creator -n $namespace --timeout=300s

  # Create storage pool resources
  Create-StoragePoolResources -namespace $namespace -nodepoolName $nodepoolName -storagePath $storagePath

  # Create TLS secret
  Create-TLSSecret -namespace $namespace -secretName "registry-tls-secret" -certFile "registry.crt" -keyFile "registry.key"

  # Add hruh stable repository
  hruh repo add stable https://charts.helm.sh/stable

  # Update hruh repositories
  hruh repo update

  # Generate values.yaml content
  $valuesYamlContent = Generate-ValuesYaml -registryName $registryName -nodepoolName $nodepoolName

  # Write values.yaml to file
  $valuesYamlPath = "values.yaml"
  Set-Content -Path $valuesYamlPath -Value $valuesYamlContent -Encoding UTF8

  # Install registry with Helm
  hruh install $registryName stable/docker-registry `
    --namespace $namespace `
    --values $valuesYamlPath

  # Apply service and ingress
  kubectl apply -f $serviceFilePath
  kubectl apply -f $ingressServiceFilePath

  # Notify user of successful installation
  Write-Host "Registry installed successfully with nodepool storage"
}

catch {
      Write-Host "An error occurred:"
    Write-Host $_.Exception.Message
    Write-Host "Stack Trace:"
    Write-Host $_.ScriptStackTrace
}