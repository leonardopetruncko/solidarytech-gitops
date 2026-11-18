# Runbook: alertas do donation-service

**Alertas cobertos:** error budget de disponibilidade ou de latência queimando rápido; nenhuma réplica disponível.

## 1. Ação automática (já aconteceu)
O self-healer reinicia o deployment (`rollout restart`), no máximo 1 vez a cada 5 min. Confira:
```
kubectl logs deploy/self-healer -n observability --tail=20
kubectl get pods -n solidarytech -l app=donation-service
```

## 2. Se o alerta continuar FIRING depois de 5 min
1. **O banco responde?** Os pods ficam NotReady se o `/ready` falha:
   `kubectl describe pod -n solidarytech -l app=donation-service | findstr Readiness`
2. **Os traces mostram onde falha?** Datadog > APM > donation-service > Errors (span do `postgresql` ou do SQS).
3. **Os logs mostram o quê?** Grafana > Explore > Loki: `{k8s_namespace_name="solidarytech"} |= "donation-service" |= "ERROR"`. Pelo `trace_id` do log, vá para o trace.
4. **Foi um deploy recente?** Argo CD > donation-service > History and Rollback, ou revert do commit no repo GitOps.
5. **A região está indisponível?** Seguir o PCN e ativar o DR: `.\scripts\dr.ps1`.

## 3. Depois
Registrar a linha do tempo e o MTTR (mensagem do self-healer no Discord) e abrir o post-mortem (modelo em `itsm-incidentes.md`).