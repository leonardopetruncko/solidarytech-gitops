# FinOps: tags, rightsizing e forecast de custos da SolidaryTech

## 1. Estratégia de tagging (no Terraform)

| Tag | Valor | Para quê |
|---|---|---|
| `Project` | `SolidaryTech` | separar o custo do projeto na fatura |
| `Environment` | `Production` | separar produção de outros ambientes |
| `CostCenter` | `NGO-Core` | rateio contábil da ONG |
| `Owner` | `leonardopetruncko` | responsável pelo recurso |
| `ManagedBy` | `Terraform` | recurso criado por código (nada "clicado") |
| `Site` | `primary` / `dr` | custo do ambiente principal x DR |
| `Service` | `donation-service`, ... | custo por microsserviço (RDS, SQS, DynamoDB, ECR) |

Como a política é garantida:

1. **`default_tags` no provider AWS:** todo recurso criado pelo Terraform recebe as tags automaticamente.
2. **Launch template dos nós:** as instâncias EC2, os discos e as interfaces de rede que o Auto Scaling do EKS cria não passam pelo provider. O `tag_specifications` aplica as mesmas tags nelas.
3. **Validação no código:** a variável `tags` tem uma `validation` que **barra o `terraform plan`** se `Project`, `Environment` ou `CostCenter` faltarem.
4. **Pipeline:** o job `FinOps - política de tags` do repositório de infraestrutura falha se as tags obrigatórias saírem do código.
5. **No Kubernetes:** o label `cost-center: ngo-core` nos pods permite o rateio do custo do cluster por serviço.

Evidência na AWS: `Resource Groups & Tag Editor` filtrando `Project = SolidaryTech`.

## 2. Rightsizing (requests e limits via GitOps)

Os valores foram definidos a partir do uso real medido no cluster, com tráfego contínuo nos 3 serviços (~5 req/s no donation-service), pelo `kubectl top pods` e pelo dashboard *Golden Metrics e Rightsizing* (painéis "uso x request"):

| Serviço | Padrão da Fase 4 (por pod) | Uso medido em carga (por pod) | Fase 5: requests → limits |
|---|---|---|---|
| donation-service (Go, 2 réplicas) | 200m / 256Mi | **7m CPU / 10 MiB** | **50m / 48Mi** → 300m / 128Mi |
| ngo-service (Python, 1 réplica) | 200m / 256Mi | **15m CPU / 87 MiB** | **50m / 160Mi** → 300m / 320Mi |
| volunteer-service (Python, 1 réplica) | 200m / 256Mi | **27m CPU / 125 MiB** | **50m / 160Mi** → 300m / 320Mi |

- Com o padrão antigo, os 4 pods reservariam **800m de CPU e 1.024 Mi de memória**. Com o rightsizing, reservam **200m (-75%)** e **416 Mi (-59%)**, mantendo folga de 2x a 7x sobre o uso medido.
- Os nós (2 × t3.large) ficaram com **9% a 14% de CPU** e **~25% de memória** com a stack inteira: aplicações, Prometheus, Grafana, Loki, OTel, Argo CD e Velero. Isso sustenta a recomendação de Savings Plan e Graviton em vez de nós maiores.
- Na carga de teste, o HPA levou o volunteer-service de 1 para 2 réplicas sozinho (53% de CPU sobre o request).
- **HPA:**** o donation-service escala de 2 a 6 réplicas e os outros de 1 a 3, sempre por CPU a 70%. Na alta (aparição na TV) a plataforma cresce e depois volta a encolher sozinha.
- **Guardrails:** `LimitRange` (valores padrão para contêineres sem requests) e `ResourceQuota` (teto do namespace). Um alerta avisa quando o uso passa de 85% da quota.
- **Imagens enxutas:** a do donation-service é distroless com 41 MB. Menos armazenamento no ECR e pull mais rápido.

## 3. Forecast mensal (us-east-1, preço on-demand, 730 h/mês)

| Item | Configuração | US$/mês |
|---|---|---|
| EKS (control plane) | 1 cluster | 73,00 |
| EC2 (nós do EKS) | 2 × t3.large on-demand | 121,47 |
| EBS dos nós | 2 × 30 GB gp3 | 4,80 |
| NAT Gateway | 1 NAT + ~20 GB processados | 33,75 |
| IP público (NAT) | 1 IPv4 | 3,65 |
| RDS PostgreSQL | db.t3.micro Single-AZ + 20 GB gp3 | 15,44 |
| Backup do RDS replicado em us-west-2 + chave KMS | ~20 GB + transferência + 1 chave | 3,30 |
| DynamoDB | on-demand + PITR (volume baixo) | 1,00 |
| SQS | < 1 milhão de requisições (free tier) | 0,00 |
| ECR | ~6 GB de imagens (10 versões por serviço) | 0,60 |
| S3 (state + backups do Velero) | < 2 GB | 0,30 |
| CloudWatch | logs do control plane desligados | 0,00 |
| **Total AWS (primário)** | | **≈ 257,31** |
| DR pilot light (backups em us-west-2) | já incluso acima | 0,00 |
| DR warm standby sempre ligado (opcional) | EKS + 1 Spot + NAT + RDS em us-west-2 | +145,00 |
| PagerDuty | plano Free (até 5 usuários) | 0,00 |
| Datadog (APM + infra) | 2 hosts, preço de tabela | ~92,00 (*) |

(*) O Datadog oferece programas para organizações sem fins lucrativos. Alternativa de custo zero: manter só a stack open source (Prometheus, Loki, Grafana e OpenTelemetry), que já cobre os SLOs e os alertas.

**Onde está o dinheiro:** computação (EC2 + EKS) responde por **~76%** do custo da AWS. É ali que as otimizações têm mais efeito.

## 4. Recomendações de otimização nativas da AWS

| # | Recomendação | Economia estimada | Esforço |
|---|---|---|---|
| 1 | **Compute Savings Plan de 1 ano** (sem pagamento antecipado) para os 2 nós | ~28% em EC2 ≈ **US$ 34/mês** | baixo: só compromisso de uso |
| 2 | **Graviton** (t4g.large, ARM): imagens multi-arch no pipeline (o Go compila nativo) | ~19% em EC2 ≈ **US$ 23/mês** | médio |
| 3 | **Spot** para workloads tolerantes (DR, ambientes de teste, réplicas extras do HPA) | até 70% nesses nós | médio (já usado no DR) |
| 4 | **Desligar ambientes de teste fora do horário** (agendamento do node group em 0) | ~65% do custo do ambiente de teste | baixo |
| 5 | VPC Endpoints de gateway para S3 e DynamoDB (**já aplicado**) | tira esse tráfego do NAT | feito |
| 6 | 1 NAT Gateway em vez de 1 por AZ (**já aplicado**, risco registrado no PCN) | US$ 33/mês | feito |
| 7 | 1 instância RDS com 2 bancos em vez de 2 instâncias (**já aplicado**) | US$ 15/mês | feito |
| 8 | Logs do control plane desligados e retenção curta no Loki/Prometheus (**já aplicado**) | evita custo de CloudWatch | feito |

**Recomendação principal para a diretoria:** Savings Plan (1) + Graviton (2) levam o custo da AWS de **~US$ 257** para **~US$ 205/mês** (-20%), sem perda de confiabilidade.

## 5. Governança de custo

- **AWS Budget** mensal filtrado pela tag `Project=SolidaryTech`, com alerta em 80% do previsto e 100% do real (`modules/budget`; desligado no AWS Academy, que bloqueia o serviço).
- **Revisão mensal:** custo por tag (`Service`, `Site`) no Cost Explorer, comparado com este forecast.
- **Alerta de capacidade** no Grafana (ResourceQuota > 85%) antes que o cluster precise crescer.
