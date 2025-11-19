provider helm {
  kubernetes = {
    config_path = "../kubeconfig.yaml"
  }
}

resource "helm_release" "cert-manager" {
  name = "cert-manager"
  chart = "oci://quay.io/jetstack/charts/cert-manager"
  create_namespace = true
  namespace = "cert-manager"
  version = "v1.19.0"
  set = [
    {
      name = "crds.enabled"
      value = "true"
    }
  ]
}

resource "helm_release" "envoy_gateway" {
  name       = "envoy-gateway"
  namespace  = "envoy-gateway-system"
  create_namespace = true

  # Official OCI Helm chart
  repository = "oci://docker.io/envoyproxy"
  chart      = "gateway-helm"
  version    = "v1.6.0"   # pin a known version; change to the latest stable as needed

}
