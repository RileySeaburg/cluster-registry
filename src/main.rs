// for windows

fn main() {
    let mut registry_name = String::new();
    // ask the user for the registry name
    println!("Enter the name of the registry: ");
    std::io::stdin()
        .read_line(&mut registry_name)
        .expect("Failed to read line");

    // ask the user for their domain name
    let mut domain = String::new();

    println!("Enter your domain name: ");

    std::io::stdin()
        .read_line(&mut domain)
        .expect("Failed to read line");

    // for private domains only
    let namespace = format!("container-registry");
    // create the registry namespace
    let registry_namespace: String = format!(
        r#"apiVersion: v1
kind: Namespace
metadata:
    name: {namespace}"#,
        namespace = namespace.trim()
    );

    let ingress_service: String = format!(
        r#"apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: container-registry-ingress
  namespace: {namespace}
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/proxy-body-size: 5g
spec:
  rules:
  - host: {domain}
    http:
      paths:
      - backend:
          service:
            name: docker-registry-public
            port:
              number: 5000
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - {domain}
    secretName: registry-tls-secret
"#,
        domain = domain.trim(),
        namespace = namespace.trim()
    );

    // declare the service 
    let service: String = format!(
        r#"apiVersion: v1
kind: Service
metadata:
    name: container-registry-public
    namespace: {namespace}
spec:
    ports:
    - port: 5000
      targetPort: 5000
    selector:
        app: docker-registry
"#,
        namespace = namespace.trim()
    );

    // write the service to a file
    std::fs::write("service.yaml", service)
        .expect("Failed to write the service to a file");

    // create the service
    std::process::Command::new("kubectl")
        .arg("apply")
        .arg("-f")
        .arg("service.yaml")
        .output()
        .expect("Failed to create the service");

    // write the registry namespace to a file
    std::fs::write("registry-namespace.yaml", registry_namespace)
        .expect("Failed to write the registry namespace to a file");

    // write the ingress service to a file
    std::fs::write("ingress-service.yaml", ingress_service)
        .expect("Failed to write the ingress service to a file");

    // create the registry namespace
    std::process::Command::new("kubectl")
        .arg("apply")
        .arg("-f")
        .arg("registry-namespace.yaml")
        .output()
        .expect("Failed to create the registry namespace");

    // create the ingress service
    std::process::Command::new("kubectl")
        .arg("apply")
        .arg("-f")
        .arg("ingress-service.yaml")
        .output()
        .expect("Failed to create the ingress service");

    std::process::Command::new("helm")
        .arg("repo")
        .arg("add")
        .arg("stable")
        .arg("https://charts.helm.sh/stable")
        .output()
        .expect("Failed to add the stable repo");

    // update helm
    std::process::Command::new("helm")
        .arg("repo")
        .arg("update")
        .output()
        .expect("Failed to update helm");

    // install the registry
    // helm install my-registry stable/docker-registry \
    //   --namespace container-registry \
    //   --set podLabels.app=docker-registry
    std::process::Command::new("helm")
        .arg("install")
        .arg(registry_name.trim())
        .arg("stable/docker-registry")
        .arg("--namespace")
        .arg(namespace.trim())
        .arg("--set")
        .arg("podLabels.app=docker-registry")
        .output()
        .expect("Failed to install the registry");

    // print to the user if it's successful

    println!("Registry installed successfully");
}
