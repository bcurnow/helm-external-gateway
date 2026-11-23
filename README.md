# helm-external-gateway

A Helm chart that puts a [Gateway API](https://gateway-api.sigs.k8s.io/) front door on backends that
live **outside** the cluster: a NAS, a Home Assistant box, a Prometheus on a VM. It renders:

| Object | Purpose |
|---|---|
| `Service` + `EndpointSlice`s | A selector-less Service whose endpoints are the external IPs. IPv4 and IPv6 addresses are split into separate slices automatically, so IPv4-only, IPv6-only and dual-stack all work. |
| `Gateway` | Listeners for HTTP, HTTPS, TLS (terminate or passthrough), TCP, UDP. |
| `HTTPRoute`, `GRPCRoute`, `TLSRoute`, `TCPRoute`, `UDPRoute` | Any number, any mix. |
| `BackendTLSPolicy` | Re-encrypt to the backend and verify it against your own CA bundle or the system roots. |

Each piece is optional. With `gateway.enabled=false` it is just a Service in front of external
endpoints (a `LoadBalancer` Service over a Ceph RGW, say).

## Install

```
helm install myapp oci://ghcr.io/bcurnow/charts/external-gateway --version 0.1.0 -f values.yaml
```

Requires the Gateway API CRDs and a Gateway implementation (which provides the GatewayClass). For
certificates, cert-manager with its Gateway API support, or a TLS secret you manage yourself. The chart
installs none of these.

## Minimal example

```yaml
gateway:
  listeners:
    - name: https
      hostname: app.example.com
      port: 443
      protocol: HTTPS
      tls:
        certificateRefs:
          - name: app-example-com-tls
services:
  - name: app
    ports:
      - port: 8080
    endpoints:
      - addresses:
          - 192.0.2.20
```

That renders an HTTPS listener for `app.example.com` on a `cilium` Gateway, an `HTTPRoute` sending `/`
to a Service on port 8080, and an EndpointSlice with the backend address. The TLS secret
`app-example-com-tls` is yours to provide, from whatever source you use.

To have cert-manager issue it, annotate the Gateway. cert-manager's
[Gateway API support](https://cert-manager.io/docs/usage/gateway/) then creates a Certificate for
every TLS listener, named by its `certificateRefs`. That support has to be enabled in cert-manager
(`config.enableGatewayAPI: true` in its chart).

```yaml
gateway:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
```

Other `gatewayClassName` values go in `gateway.gatewayClassName`. Dual-stack needs more addresses and an explicit policy, since the chart never guesses the Service's
families:

```yaml
services:
  - name: app
    ipFamilyPolicy: PreferDualStack
    ports:
      - port: 8080
    endpoints:
      - addresses:
          - 192.0.2.20
          - "2001:db8::20"
```

Re-encrypt to a backend that serves TLS with a private CA:

```yaml
services:
  - name: app
    ports:
      - port: 443
        appProtocol: https
    backendTLS:
      validation:
        hostname: backend.example.com
        caCertificateRefs:
          - kind: ConfigMap
            name: my-ca
```

The CA ConfigMap is yours to create; the chart only references it.

More cases are in [`charts/external-gateway/ci/`](charts/external-gateway/ci): IPv4-only HTTP,
IPv6-only HTTPS, TLS passthrough, TCP and UDP, a LoadBalancer Service with no Gateway, ExternalName,
and a kitchen-sink that sets metadata on every object.

## How values map to objects

Every object follows one rule: a few **reserved keys** are chart controls, and **every other key is
copied verbatim into the object's `spec`**. So any field the CRD defines works, including ones added
in future Gateway API releases, with no chart change.

| Values key | Object | Reserved keys (everything else is spec) |
|---|---|---|
| `gateway` | Gateway | `enabled name labels annotations` |
| `routes[]` | `kind`-dependent Route | `kind apiVersion name labels annotations` |
| `services[]` | Service (+ slices, policy) | `name labels annotations ports endpoints endpointSlice backendTLS` |
| `services[].backendTLS` | BackendTLSPolicy | `name labels annotations` |

`labels` and `annotations` are available on every object, merged over `commonLabels` and
`commonAnnotations`. `apiVersions` overrides the apiVersion per kind, for older or experimental
Gateway API installs. Everything is created in the release namespace. The GatewayClass, CA
ConfigMaps and TLS secrets you reference are not managed by the chart.

### Defaults, so the common case is short

- **Names:** every `services[]` and `routes[]` item needs a `name`. Only the Gateway defaults to the
  release name, since there is exactly one.
- **Routes:** with no `routes` at all, one HTTPRoute named after the release sends everything to the
  service. For each route, `parentRefs` point at this release's Gateway, and with no `rules` everything goes to the service. In your own `rules`, a `backendRef`
  that omits `name` (and `port`) is filled with the service, so a `backendRef` that only sets
  `weight` works. This applies only when there is exactly one service; with several, name the
  service in every `backendRef`. A route with no `hostnames` serves its listeners' hostnames, except
  TLSRoute, where the CRD requires them.
- **EndpointSlices:** named `<service>-<port>` and `<service>-<port>-v6`; `conditions` defaults to
  `ready: true`. The numeric slice port comes from `endpointPort`, else `targetPort`, else `port`.
  Set `endpointPort` when `targetPort` is a name.
- **IP families:** addresses are validated as IPv4 or IPv6 by the values schema, then split into one
  slice per family. With `ipFamilies` set, only those families get a slice, and an endpoint with no
  address in them fails the render. If the addresses use both families, `ipFamilyPolicy` (not
  `SingleStack`) or `ipFamilies` must be set, or the render fails. Nothing is derived for you.
  `helm --skip-schema-validation` turns the address check off.
- **Adopting existing objects:** the Gateway is named after the release, so set `fullnameOverride`
  or `gateway.name` to match, and give services and routes the names they already have.

### Notes

- TCPRoute and UDPRoute are experimental-channel Gateway API; they default to `v1alpha2`. TLSRoute and
  BackendTLSPolicy are `v1` in recent Gateway API; use `apiVersions` on older installs.
- EndpointSlices with `addressType: FQDN` are not generated. Use `service.type: ExternalName`.
- Values are validated by `values.schema.json`; native fields (`listeners`, `rules`, ...) are
  deliberately left open.

## Development

```
helm lint charts/external-gateway -f charts/external-gateway/ci/kitchen-sink-values.yaml
helm template t charts/external-gateway -f charts/external-gateway/ci/dual-stack-https-values.yaml
```

CI lints and renders every `ci/*-values.yaml` fixture and validates the output with kubeconform
against the Gateway API and cert-manager schemas. Pushing a tag `vX.Y.Z` that matches `Chart.yaml`
publishes the chart to `oci://ghcr.io/<owner>/charts`.

## License

Apache-2.0
