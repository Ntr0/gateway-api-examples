provider "kubernetes" {
  config_path = local_sensitive_file.kube_config.filename
}

resource "kubernetes_manifest" "envoy-config" {
  manifest = {
    "apiVersion" = "gateway.envoyproxy.io/v1alpha1"
    "kind" = "EnvoyProxy"
    "metadata" = {
      "name" = "envoy-proxy-config"
      "namespace" = "envoy-gateway-system"
    }
    "spec" = {
      "provider" = {
        "kubernetes" = {
          "envoyDeployment" = {
            "pod" = {
              "nodeSelector" = {
                "cloud.ionos.com/nodepool-name" = ionoscloud_k8s_node_pool.loadbalancer.name
              }
            }
          }
          "envoyService" = {
            "annotations" = {
              "cloud.ionos.com/node-selector" = "cloud.ionos.com/nodepool-name=${ionoscloud_k8s_node_pool.loadbalancer.name}"
            }
            "externalTrafficPolicy" = "Local"
            "type" = "LoadBalancer"
          }
        }
        "type" = "Kubernetes"
      }
    }
  }
}
resource "kubernetes_manifest" "gateway-class" {
  manifest = {
    "apiVersion" = "gateway.networking.k8s.io/v1"
    "kind" = "GatewayClass"
    "metadata" = {
      "name" = "envoy-gateway-class"
    }
    "spec" = {
      "controllerName" = "gateway.envoyproxy.io/gatewayclass-controller"
      "parametersRef" = {
        "group" = "gateway.envoyproxy.io"
        "kind" = "EnvoyProxy"
        "name" = "envoy-proxy-config"
        "namespace" = "envoy-gateway-system"
      }
    }
  }
}
