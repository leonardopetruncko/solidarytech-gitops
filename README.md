# SolidaryTech - GitOps, Observabilidade e SRE

Tudo o que roda no cluster EKS, sincronizado pelo **Argo CD** (App-of-Apps). Nenhum deploy é feito com `kubectl` manual.

```
argocd/                    root-app + projetos + Applications
apps/base/                 namespace + LimitRange + ResourceQuota (guardrails FinOps)
apps/<serviço>/            Deployment (rightsizing), Service, HPA, PDB, Job de init do banco
observability/values/      kube-prometheus-stack, Loki, OpenTelemetry Collector
observability/manifests/   SLOs (PrometheusRule), alertas por burn rate, dashboards, self-healer
docs/                      SRE/SLO, PCN (DR), ITSM, FinOps, runbook
```

## Documentação

| Documento | Conteúdo |
|---|---|
| [docs/sre-slo.md](docs/sre-slo.md) | SLIs, SLOs, SLA, error budget, burn rate e MTTR |
| [docs/pcn.md](docs/pcn.md) | Plano de Continuidade de Negócios: RTO, RPO e estratégia de DR |
| [docs/itsm-incidentes.md](docs/itsm-incidentes.md) | ciclo de vida do incidente, AIOps, comunicação e post-mortem |
| [docs/finops.md](docs/finops.md) | tags, rightsizing, forecast de custos e recomendações |
| [docs/runbook-donation.md](docs/runbook-donation.md) | runbook dos alertas do donation-service |

Infraestrutura: [solidarytech-infra](https://github.com/leonardopetruncko/solidarytech-infra) · Código: [solidarytech-app](https://github.com/leonardopetruncko/solidarytech-app)