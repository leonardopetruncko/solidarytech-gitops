# Plano de Continuidade de Negócios (PCN) da SolidaryTech

**Documento executivo.** Objetivo: **as doações não podem parar**, nem se uma região inteira da AWS cair.

## 1. Processos críticos e objetivos de recuperação

| Processo / dado | Criticidade | RPO (quanto dado pode ser perdido) | RTO (em quanto tempo volta) |
|---|---|---|---|
| **Doações** (`donation-service` + banco `donation_db`) | **Crítica** (Hot Path) | **≤ 5 min** | **≤ 30 min** (perda de região) · **≤ 2 min** (falha de pod ou nó) |
| Eventos de doação (fila SQS) | Alta | 0 dentro da região (SQS replica em 3 AZs) | junto com o serviço |
| Cadastro de ONGs (`ngo_db`) | Média | ≤ 5 min | ≤ 30 min |
| Voluntários (DynamoDB) | Baixa | segundos na região (PITR) · 24h entre regiões | ≤ 60 min |
| Estado do cluster (manifestos, Secrets) | Alta | **0** para manifestos (Git) · **≤ 15 min** para Secrets e estado (Velero) | ≤ 30 min |

- **RPO (Recovery Point Objective):** o máximo de dados, em tempo, que se aceita perder.
- **RTO (Recovery Time Objective):** o tempo máximo até o serviço voltar.

## 2. Cenários de desastre e resposta

| # | Cenário | Proteção | Recuperação | RTO |
|---|---|---|---|---|
| 1 | Pod com defeito ou falha silenciosa | 2 réplicas, readiness probe, alerta de SLO | self-healer faz rollout restart | ~2 min |
| 2 | Nó EC2 cai | réplicas espalhadas por nó e AZ (topologySpread) + PDB | Kubernetes reagenda; Auto Scaling repõe o nó | ~1 a 5 min |
| 3 | Deploy com bug | pipeline com testes e scans; rolling update sem indisponibilidade | rollback pelo Git (Argo CD) | ~5 min |
| 4 | Banco corrompido ou dado apagado por engano | backup automático com PITR (7 dias) | restore point-in-time | ~20 min |
| 5 | Perda de uma AZ | nós em 2 AZs; RDS Multi-AZ recomendado para produção | failover do RDS (Multi-AZ) ou PITR | 2 a 20 min |
| 6 | **Perda da região us-east-1** | backups do RDS replicados + Velero no S3 de **us-west-2** + IaC | **`scripts/dr.ps1`**: sobe o ambiente espelho em us-west-2 | **≤ 30 min** |

## 3. Estratégia de Disaster Recovery

A SolidaryTech usa as **duas opções** do desafio, combinadas:

### Opção A: backup multi-região com o Velero
- O Velero roda no cluster e grava backups no bucket `solidarytech-velero-<conta>`, em **us-west-2**, fora da região primária.
- **A cada 15 min:** namespaces `solidarytech` e `observability`, retenção de 72h.
- **Diário:** cluster inteiro, retenção de 30 dias.
- Bucket versionado, criptografado e privado. Os backups antigos passam para STANDARD_IA (mais barato) e expiram em 90 dias.
- O Velero acessa o S3 com a role do nó (IMDSv2): **nenhuma chave fica guardada no cluster**.
- **Prova de restauração:** `scripts/velero-demo.ps1` faz um backup, apaga o Secret do donation-service (senha do banco e fila, que **não existe no Git**) e o restaura do bucket de us-west-2. O script confere que o Secret voltou idêntico ao original. Testado em 18/11/2026: backup e restore com status *Completed*.

### Opção B: infraestrutura ativo-passivo (Warm Standby / Pilot Light)
- O **mesmo código Terraform** sobe em outra região, com outro workspace (`dr`) e outro arquivo de variáveis (`envs/dr.tfvars`): **1 comando**, `.\scripts\dr.ps1`.
- O que o comando faz:
  1. Encontra o backup do RDS primário replicado em us-west-2 e sobe o banco de DR **já com os dados** (restore point-in-time).
  2. Sobe rede, EKS (nós **Spot**), DynamoDB, SQS, Argo CD e Velero. No DR o bucket do Velero fica em modo **só leitura**.
  3. Restaura o último backup do Velero (Secrets e recursos).
  4. Liga o GitOps: o Argo CD lê o **mesmo repositório**, e as aplicações sobem iguais às do primário.
- **Decisão de custo (FinOps):** para o orçamento de uma ONG, o DR fica em **pilot light**. Só os dados (backups replicados e Velero) ficam sempre em us-west-2, a ~US$ 3/mês. O ambiente é levantado sob demanda. Um warm standby sempre ligado custaria ~US$ 145/mês e reduziria o RTO para ~5 min (avaliar quando a receita de doações justificar).

## 4. Acionamento (quem decide e como)

1. **Detecção:** alertas de SLO (burn rate) e AWS Health Dashboard indicando falha regional.
2. **Decisão:** o Incident Commander declara desastre se a região estiver indisponível por mais de **15 min**, sem previsão de retorno.
3. **Execução:** `.\scripts\dr.ps1`. O tempo total é medido e impresso pelo script (RTO real).
4. **Redirecionamento:** troca do DNS (Route 53 failover) para o endpoint de us-west-2.
5. **Comunicação:** modelo SEV1 do documento de ITSM: diretoria, ONGs e doadores.
6. **Retorno (failback):** com a região primária de volta, backup do DR → restore no primário → DNS de volta → `.\scripts\dr.ps1 -Destruir`.

## 5. Testes do plano

| Teste | Frequência | Como |
|---|---|---|
| Restauração de backup do cluster | mensal | `scripts/velero-demo.ps1` |
| Falha de aplicação (Game Day) | mensal | `scripts/simular-falha.ps1` e medição do MTTR |
| Failover de região | trimestral | `scripts/dr.ps1`: medir o RTO real e comparar com a meta de 30 min |

## 6. Segurança aplicada à continuidade

- **Segredos fora do Git:** criados no cluster a partir de um arquivo local ignorado pelo Git.
- **Menor privilégio no banco:** cada serviço tem o próprio usuário e só acessa o próprio banco.
- **Pods endurecidos:** contêineres não-root, sistema de arquivos só leitura, capabilities removidas, seccomp.
- **Criptografia:** RDS, EBS, S3, SQS e DynamoDB criptografados em repouso; conexão com o banco por TLS (`sslmode=require`).
- **DevSecOps no pipeline:**
  - SAST: gosec e bandit.
  - SCA e scan de imagem: Trivy.
  - Scan do Terraform: Trivy config, com as exceções justificadas em `.trivyignore`.
