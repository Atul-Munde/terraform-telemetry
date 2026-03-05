# ALB Ingress for vmselect UI and query API
# Only created when create_ingress = true.
# Routes all traffic through vmselect (port 8481) — or via VMAuth (see auth.tf)
# depending on vmauth_enabled.
#
# Prerequisites:
#   - AWS Load Balancer Controller installed in the cluster
#   - ACM certificate ARN set via var.alb_certificate_arn
#   - var.vmselect_ingress_host set to a valid hostname

resource "kubernetes_ingress_v1" "vmselect_ui" {
  count = var.create_ingress ? 1 : 0

  metadata {
    name      = "vmselect-ui"
    namespace = var.namespace
    labels = merge(local.common_labels, {
      "app.kubernetes.io/component" = "vmselect"
    })
    # local.alb_annotations already contains: scheme=internet-facing,
    # target-type=ip, certificate-arn, listen-ports=HTTPS:443, ssl-redirect,
    # healthcheck-path=/health, group.name=var.alb_group_name.
    # Adding vmselect UI as a new rule on the existing intangles-ingress ALB —
    # no new load balancer is created.
    #
    # Root "/" redirects to VMUI (/select/0/vmui/) via an ALB redirect action.
    # All other paths (/select/..., /health, etc.) forward to vmselect directly.
    annotations = merge(local.alb_annotations, {
      "alb.ingress.kubernetes.io/actions.redirect-to-vmui" = jsonencode({
        type = "redirect"
        redirectConfig = {
          path       = "/select/0/vmui/"
          statusCode = "HTTP_301"
        }
      })
    })
  }

  spec {
    ingress_class_name = var.ingress_class_name

    rule {
      host = var.vmselect_ingress_host != "" ? var.vmselect_ingress_host : null

      http {
        # Exact "/" → 301 redirect to the VMUI path
        path {
          path      = "/"
          path_type = "Exact"
          backend {
            service {
              name = "redirect-to-vmui"
              port {
                name = "use-annotation"
              }
            }
          }
        }

        # Prefix "/" → forward to vmselect (or vmauth) for all API/UI sub-paths
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = var.vmauth_enabled ? "vmauth-vmauth" : "${local.vmselect_svc}"
              port {
                number = var.vmauth_enabled ? 8427 : 8481
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubectl_manifest.vmcluster]
}
