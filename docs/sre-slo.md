# SRE: SLIs, SLOs, SLA e error budget do donation-service

O `donation-service` é o **Hot Path** da SolidaryTech: se ele para, a doação não acontece.
Por isso os indicadores de confiabilidade da plataforma são medidos nele.

## Definições

| Termo | O que é | Para quem |
|---|---|---|
| **SLI** (indicador) | Medida objetiva da experiência do doador, calculada a partir de dados reais | Time técnico |
| **SLO** (objetivo) | Meta interna para o SLI, numa janela de 30 dias | Time técnico e diretoria |
| **SLA** (acordo) | Compromisso formal com as ONGs parceiras, **mais folgado** que o SLO | ONGs |
| **Error budget** | `100% - SLO`: quanto de falha é aceitável no mês | Decide entre velocidade e estabilidade |

O SLO é mais rígido que o SLA de propósito: o alerta interno toca **antes** de o compromisso com as ONGs ser quebrado.

## SLIs e SLOs (Golden Metrics: erros e latência)

| # | SLI | Fórmula (eventos bons ÷ eventos válidos) | SLO (30 dias) | Error budget |
|---|---|---|---|---|
| 1 | **Disponibilidade** | requisições ao donation-service **sem HTTP 5xx** ÷ total de requisições | **99,5%** | 0,5% ≈ **3h36min** de indisponibilidade por mês |
| 2 | **Latência** | doações (`POST /donations`) respondidas em **até 250 ms** ÷ total de doações | **99%** | 1% das doações pode passar de 250 ms |

- **Eventos válidos:** requisições reais de usuários. Health checks (`/health`, `/ready`) não geram span e ficam fora do cálculo.
- **HTTP 4xx não conta como erro:** é erro do cliente (ex.: valor inválido), não indisponibilidade do serviço.
- **Fonte:** spans de servidor do OpenTelemetry → connector `spanmetrics` do OTel Collector → Prometheus.

## SLA com as ONGs parceiras

| Compromisso | Valor mensal | Se não for cumprido |
|---|---|---|
| Disponibilidade da plataforma de doações | **99,0%** (até 7h18min fora do ar) | relatório de incidente (post-mortem) enviado às ONGs em até 5 dias úteis |
| Latência das doações | p99 ≤ **500 ms** | plano de ação publicado e prioridade máxima no backlog |
| Comunicação de incidente SEV1 | primeira mensagem em até **30 min** | revisão do processo de comunicação |

Como a SolidaryTech é sem fins lucrativos, o SLA não prevê multa: a contrapartida é **transparência** (post-mortem público) e prioridade de correção.

## Como está implementado (como código)

| Peça | Arquivo |
|---|---|
| Recording rules dos SLIs, burn rate e budget restante (PrometheusRule) | `observability/manifests/slo/donation-slo-rules.yaml` |
| Alertas por burn rate (Grafana Alerting) | `observability/manifests/alerting/rules.yaml` |
| Dashboard SRE (só SLOs e error budget) | `observability/manifests/dashboards/solidarytech-sre-slo.json` |
| Dashboard Golden Metrics (latência, tráfego, erros, saturação) | `observability/manifests/dashboards/solidarytech-golden.json` |

## Alertas por burn rate (Google SRE Workbook)

Burn rate = velocidade de consumo do error budget. **1x** gasta o budget em exatamente 30 dias.

| Alerta | Condição | Significado | Destino |
|---|---|---|---|
| Queima rápida (disponibilidade) | burn rate > **14,4x** em 1h **e** em 5 min | 2% do budget do mês em 1 hora | PagerDuty + Discord + self-healer |
| Queima rápida (latência) | burn rate > **14,4x** em 1h **e** em 5 min | idem, para lentidão | PagerDuty + Discord + self-healer |
| Queima lenta (disponibilidade) | burn rate > **6x** em 6h **e** em 30 min | 5% do budget em 6 horas | Discord (ticket) |

A janela longa evita alertar por pico isolado (sem alert fatigue). A janela curta faz o alerta **resolver logo** depois da correção.

## Política de error budget

| Budget restante | Ação |
|---|---|
| > 50% | Deploys normais; espaço para experimentar |
| 25% a 50% | Deploys só com revisão extra e canário |
| < 25% | Congela features: o time prioriza confiabilidade |
| Esgotado (SLO violado) | Só correções; post-mortem obrigatório; comunicação às ONGs |

## Redução do MTTR

| Fase do incidente | Sem a stack (cenário original) | Com a stack da SolidaryTech |
|---|---|---|
| Detecção | usuário reclama (horas) | alerta de burn rate em ~1 a 2 min; Watchdog (Datadog) detecta anomalia |
| Diagnóstico | logs espalhados nos pods | trace distribuído (Datadog APM), log ligado ao trace pelo `trace_id` (Loki) |
| Mobilização | ligações e mensagens | PagerDuty aciona o plantão; Discord recebe o contexto completo e o link do runbook |
| Correção | `kubectl` manual | self-healer faz o rollout restart sozinho (~10 s) |
| Verificação | "parece que voltou" | alerta RESOLVED + **MTTR calculado e postado** pelo self-healer |

Resultado medido nos testes: **MTTR de ~2 a 3 min**, contra horas no cenário sem observabilidade.
