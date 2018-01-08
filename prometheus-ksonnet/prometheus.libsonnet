local k = import "kausal.libsonnet";

k {
  _config+:: {
    prometheus_external_hostname: "http://prometheus.%s.svc.cluster.local" % $._config.namespace,
    prometheus_path: "/",
  },

  local policyRule = $.rbac.v1beta1.policyRule,

  prometheus_rbac: $.util.rbac("prometheus", [
    policyRule.new() +
    policyRule.withApiGroups([""]) +
    policyRule.withResources(["nodes", "nodes/proxy", "services", "endpoints", "pods"]) +
    policyRule.withVerbs(["get", "list", "watch"]),

    policyRule.new() +
    policyRule.withNonResourceUrls("/metrics") +
    policyRule.withVerbs(["get"]),
  ]),

  local container = $.core.v1.container,

  prometheus_container::
    container.new("prometheus", $._images.prometheus) +
    container.withPorts($.core.v1.containerPort.new("http-metrics", 80)) +
    container.withArgs([
      "--config.file=/etc/prometheus/prometheus.yml",
      "--web.listen-address=:80",
      "--web.external-url=%s%s" % [$._config.prometheus_external_hostname, $._config.prometheus_path],
      "--web.enable-lifecycle",
    ]),

  prometheus_watch_container::
    container.new("watch", $._images.watch) +
    container.withArgs([
      "-v", "-t", "-p=/etc/prometheus",
      "curl", "-X", "POST", "--fail", "-o", "-", "-sS",
      "http://localhost:80%s-/reload" % $._config.prometheus_path,
    ]),

  local deployment = $.extensions.v1beta1.deployment,

  prometheus_deployment:
    deployment.new("prometheus", 1, [
      $.prometheus_container,
      $.prometheus_watch_container,
    ]) +
    $.util.configVolumeMount("prometheus-config", "/etc/prometheus") +
    deployment.mixin.spec.template.spec.withServiceAccount("prometheus") +
    deployment.mixin.spec.template.spec.securityContext.withRunAsUser(0),

  prometheus_service:
    $.util.serviceFor($.prometheus_deployment),
}
