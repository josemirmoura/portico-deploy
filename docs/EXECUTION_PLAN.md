# Pórtico Deploy | Plano canônico de execução

**Estado-base verificado em 03/11/2026:** repositório `josemirmoura/portico-deploy`, HEAD `0de5b7dfa99e8fd5a8338da421aee6421c96fb2e`. CI de testes unitários e sintaxe aprovado nesse SHA; **sem comprovação de instalação E2E, publicação HTTP, persistência ou uso operacional no SRV-IA/VPS**. As issues [#1](https://github.com/josemirmoura/portico-deploy/issues/1)–[#6](https://github.com/josemirmoura/portico-deploy/issues/6) são demandas, não provas de entrega.

## 1. Missão e resultado de produto

O usuário cadastra um servidor **uma vez** com autorização explícita; cadastra cada aplicação com configurações declarativas e escopo próprio; depois pede **"faça o deploy do projeto X no ambiente Y"**. Uma integração autorizada aciona a publicação pelo GitHub Actions, acompanha logs/healthcheck e reporta o SHA, o resultado e o rollback disponível. Deve haver modo automático por push, ativado explicitamente.

Princípio de execução: **GitHub Actions + GitHub CLI + SSH/Ansible apenas quando trouxerem benefício real**. Sem criar um orquestrador generalista, painel obrigatório ou clone de Pórtico Infinity. Não colocar runner no host com Docker socket/root genérico. Evitar desenvolvimento de infraestrutura que já é resolvida pelo GitHub.

## 2. Contrato mínimo do MVP

1. **Cadastro do servidor:** identificar host, pré-requisitos, identidade, escopo, endpoints permitidos e ambiente; instalação auditável e repetível, com dry-run e opção de desfazer a própria configuração. Nenhuma modificação de proxy, rede, DNS, VPN ou software alheio.
2. **Cadastro de aplicação:** `repo`, `project`, `environment`, `target`, `branch`, `artifact_type`, `healthcheck`, `rollback_policy`, identidade e limites. Cada par projeto/ambiente tem permissão segregada. Repositórios com runner persistente devem ser privados. O registry será versionado como configuração, **sem dados sensíveis**.
3. **Ciclo:** validar → build/testar no GitHub-hosted → publicar artefato imutável → deploy no destino autorizado → healthcheck → sucesso ou rollback → evidências.
4. **Comando de IA:** API/integração de menor privilégio para `deploy.start`, `deploy.status`, `deploy.logs`, `deploy.rollback`. Se GitHub Actions API/connector bastar, NÃO construir serviço MCP adicional. A IA nunca adquire SSH/root implícito.
5. **Dois destinos:** SRV-IA e VPS, com políticas independentes. **Preservar VPS como túnel/borda dos projetos existentes**; publicar aplicações nela somente após configuração e autorização específica. Para uso no SRV-IA, respeitar serviços operacionais existentes.

## 3. Marcos de entrega (ordem fixa)

| Marco | Entrega verificável | Gate de aceite | Intervenção do proprietário |
| --- | --- | --- | --- |
| **M0 — Fundação** | Repositório, arquitetura, testes, motor de release estática, scripts iniciais de bootstrap e workflow | Código em GitHub + CI no SHA, **sem alegação de deploy real** | Nenhuma. **Já entregue parcialmente como base experimental** |
| **M1 — Deploy estático seguro** | Corrigir falhas do bootstrap/runner; instalar e publicar em Linux descartável, negar entradas maliciosas; rollback e uninstall seguros | E2E com app sintético, workflow real, SHA, HTTP, rollback, cleanup, logs e checagem de fronteiras. Issues #1 e #2 | Nenhuma em servidores reais |
| **M2 — Cadastro reutilizável** | `host enroll` uma vez; `app add` declarativo e idempotente; reconciliação e `app remove` sem perda de dados | Dois projetos isolados no mesmo host descartável, repetição sem duplicação, rollback da configuração, segurança por identidade. Issue #5 | Nenhuma em servidores reais |
| **M3 — Deploy por comando** | Adaptador simples para comando autenticado da IA disparar e acompanhar workflow e rollback, sem permissões gerais | E2E real IA → GitHub → runner → health → status; autorização negativa; logs/correlação. Issue #3 | Conectar/autorizar integração da IA, somente quando indispensável |
| **M4 — Aplicações reais e múltiplos destinos** | Um adaptador de **serviço** priorizado por uso (primeiro Python/Node sem privilégio amplo); registro de SRV-IA e VPS; Docker/Compose só após revisão específica | Publicação de app sintético por tipo e em hosts descartáveis distintos; falhas recuperadas; sem afetar redes, serviços ou projetos externos. Issue #4 | Aprovar quais aplicações e destinos entram no UAT |
| **M5 — UAT, pacote e GO/NO-GO** | Release candidate por SHA, instalação reproduzível, segurança, runbook, documentação, métricas, limites e rollback demonstrados | Teste pessoal do proprietário em ambiente operacional autorizado + GO explícito; NO-GO mantém pré-lançamento. Issue #6 | **UAT e decisão final GO/NO-GO** |

**Regra de prioridade:** somente um marco ativo por vez. M0 é baseline; a próxima tarefa é **M1**. M2/M3/M4 não devem ser implementados em paralelo por conveniência. Testes e correções surgidos em um marco pertencem ao próprio marco.

## 4. Fora de escopo até M5

- Painel web próprio, cobrança/SaaS, marketplace, multi-tenant empresarial, Kubernetes, agente genérico de administração, root shell, alterações de Pórtico Community/Infinity.
- Gerenciamento de DNS, Traefik, WireGuard, infraestrutura da VPS além do destino aprovado, e automação autônoma sem comando/agendamento autorizado.
- Adaptação prematura do ParecIA: sua CI/CD atual funciona; **não substituir** antes de prova e GO específicos. Primeiro validar com aplicações descartáveis.
- Suporte universal a toda stack. Docker/Compose é uma expansão condicionada a isolamento adequado, e **não deve bloquear** o aceite do MVP básico.

## 5. Evidências, métricas e segurança

Para cada marco, publicar SHA, workflow/logs, teste positivo e negativo, status **feito/parcial/pendente**, riscos residuais, instrução de rollback e issue atualizada. CI verde comprova CI; E2E efêmero comprova laboratório; produção exige UAT.

Indicadores de aceite: porcentagem de deployments com healthcheck aprovado, rollback com tempo medido, integridade da release por SHA, ausência de permissões fora do escopo, repetibilidade da configuração (segunda execução sem efeitos) e número de intervenções manuais. **Não inventar metas numéricas ou percentuais sem medições**; medi-las em M1/M2 para definir SLOs.

Host e projeto têm autorização duradoura **revogável**, mas tokens, sessões e jobs mantêm expiração própria. Runner persistente executa workflows não confiáveis com sua identidade: separar por repositório/projeto, exigir revisão/proteção de workflows e política de acesso e impedir execução de PR não confiável no runner do destino. Segredos nunca nos artefatos.

## 6. Rotina para continuidade por outra IA

1. Ler `AGENTS.md` e este plano, HEAD, issues #1–#6 e CI; confrontar código com documentação.
2. Escolher o **primeiro gate não cumprido**. Fazer a menor alteração necessária; testar e registrar prova no SHA exato. Não recomeçar arquitetura nem abrir novas frentes.
3. Utilizar runner/VM descartável para M1–M4. **Não operar SRV-IA/VPS reais** sem autorização específica do proprietário.
4. Após cada rodada: escrever marco atual, evidência obtida, bloqueio, uma próxima tarefa e eventual ação humana.
5. Nenhum anúncio de v1.0, promoção para produção ou promessa "cole e use" sem M5, UAT e GO explícito.

**Foco de produto:** um comando de instalação controlada e um comando de deploy auditável. Todo o resto deve justificar por que é necessário a esse fluxo.
