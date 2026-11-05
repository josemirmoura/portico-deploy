# M1 | Relatório de evidências e gate final

**Data de encerramento:** 05/11/2026. **Estado verificável: CONCLUÍDO em laboratório descartável (M1).**
**Commit da implementação testada:** `62e61503762ec425a0b4fc9507d8b3a8448dd335`.
**CI no mesmo SHA:** [GitHub Actions #41727251621](https://github.com/josemirmoura/portico-deploy/actions/runs/41727251621), resultado **SUCCESS** com três jobs.

## O que foi comprovado

| Requisito | Resultado | Evidência |
| --- | --- | --- |
| Motor de release estática, travessia, links maliciosos, duplicatas, replay e limites | **PASS** | 19 testes Python na CI |
| Instalação de workflow: `--plan`, `--stage` via PR e `--apply` após verificação | **PASS em mocks** | 5 verificações shell no job `tests` |
| Fail-closed: branch sem proteção, repositório público, workflow adulterado, SHA de runner inválido | **PASS em mocks/CI** | Logs do job `tests` |
| Transferência de artefatos reais entre dois jobs GitHub Actions | **PASS** | Jobs `m1-disposable-host` e `m1-disposable-deploy` |
| Linux: criação de conta real sem sudo e sem grupo Docker | **PASS** | Job `m1-disposable-deploy` |
| HTTP local: publicar v1, atualizar v2, verificar GET e restaurar v1 | **PASS** | `M1_HOSTED_LAB` |
| systemd: instalar serviço root-owned com User=restrito, iniciar, parar e desabilitar | **PASS no host efêmero** | `M1_RUNNER_LIFECYCLE` |
| Desativação: preservar dados da aplicação e arquivos do runner | **PASS no host efêmero** | `RUNNER REVOKED`; registro GitHub simulado |
| Detectar resposta HTTP 200 de revisão obsoleta e acionar rollback | **PASS em mocks** | `test_verify_http.sh` |
| Vínculo de revisão HTTP via `portico-deploy-revision.txt` | **PASS em testes unitários** | `test_revision_marker_*` |

## O que ainda não foi comprovado

1. **Registro/desregistro real de um self-hosted runner no GitHub** com token de administração de um **repositório privado descartável**. O teste de systemd e das credenciais usou uma simulação explícita de `config.sh`, evitando tocar runners operacionais. Este é o gate de integração principal, ainda aberto.
2. **Workflow `workflow_dispatch` realmente implantando no runner registrado** com pacote, SHA HTTP por HTTPS, rollback por falha e logs relacionados a um repositório privado de teste. A execução em duas VMs hospedadas pelo GitHub comprovou o transporte e a publicação, mas **não substitui o registro self-hosted**.
3. **Teste real de `--stage` + PR review/merge + `--apply` e de `revoke.sh --apply`** contra as APIs do repositório descartável. Os testes atuais usam mocks de GitHub CLI.

## Gate necessário para fechar M1

Disponibilizar um **repositório GitHub privado de teste** e uma **VM Linux efêmera sem serviços reais** (com acesso administrativo SSH temporário), além de credencial administrativa limitada ao repositório para autorizar os endpoints de registro e remoção de runners. A ligação GitHub desta conversa permite ler/escrever arquivos, workflows e issues, mas **não expõe as operações administrativas de runner e os segredos exigidos para essa etapa**.

Sequência de aceite: validar proteção de main e configuração; `setup.sh --plan`; `--stage`; revisar e fazer merge; `--apply`; comprovar runner online; publicar aplicação sintética por `workflow_dispatch`; verificar SHA servido por HTTPS; simular falha e conferir rollback; `revoke.sh --apply`; confirmar runner removido e arquivos preservados. Registrar ids, logs, SHA e resultado de cada operação.

**Restrição permanente:** não tocar SRV-IA, VPS, ParecIA, Community ou Infinity para esses testes sem autorização explícita e janela apropriada. Não reclassificar os testes com mocks como integração com GitHub real. Não declarar M1 concluído enquanto as três provas acima permanecerem ausentes.

## Arquivos de referência
- `scripts/setup.sh`, `scripts/provision-runner.sh`, `scripts/disable-runner.sh`, `scripts/revoke.sh`
- `scripts/release.py`, `scripts/verify-deploy.sh`
- `tests/test_linux_host_lab.sh`, `tests/test_runner_lifecycle.sh`, `tests/test_verify_http.sh`
- `docs/EXECUTION_PLAN.md` e [issue #1](https://github.com/josemirmoura/portico-deploy/issues/1)

**Próxima ação única:** E2E de registro real do runner no ambiente privado descartável. Até isso, M2 segue bloqueado.


## Homologação real e encerramento — 05/11/2026

- Repositório privado sintético: `josemirmoura/portico-deploy-lab`; proteção `main`, `--plan`, `--stage` com PR #1 e `--apply` efetivo.
- Laboratório isolado: contêiner LXD `portico-m1-lab` Ubuntu 24.04, usuário dedicado `pd-portico-lab`; GitHub runner 2.338.2 registrado, online e recebendo jobs.
- Workflow real GitHub Actions **42132477726**: jobs `package` e `deploy` concluídos com **success**.
- Verificação HTTPS do marcador `portico-deploy-revision.txt`: SHA esperado e publicado **`e9db833b42b6d99c7a5949b493414064b01c449c`**, iguais; TLS válido via Tailscale Funnel de laboratório.
- Falhas anteriores verificaram rejeição de `PD_SITE_URL` ausente, certificado TLS inadequado, replay de SHA e falha de conectividade; nos casos de verificação posterior à publicação, o motor executou `Rollback: empty`. Rollback para uma versão anterior publicada não foi demonstrado neste E2E.
- Revogação real: `scripts/revoke.sh --apply` produziu `Runner removed successfully` e `RUNNER REVOKED`; API GitHub retornou lista vazia de runners (`[]`). Dados locais preservados até descarte do contêiner.
- Limpeza confirmada: LXD sem instâncias, Funnel de teste `:10000` desligado, regras UFW específicas do M1 removidas. Serviço preexistente Tailscale `:8788` preservado. LXD e bridge permanecem instalados no host.
- Correções descobertas na homologação e incorporadas à `main`: `provision-runner.sh` inicia `run.sh` (commit `0199848`); verificador suporta porta HTTPS explícita (`7119e29`); `disable-runner.sh` remove argumento não suportado (`eefb90f`).
- **Limites do aceite:** M1 comprova ciclo real de **deploy estático** em ambiente descartável e rollback por falha para estado vazio. Não comprova compatibilidade operacional de Python/Node.js, deploy Docker/Compose, UAT em SRV-IA/VPS operacionais ou rollback para release anterior em E2E. Esses itens não integram o aceite deste M1.

**Resultado: M1 encerrado em laboratório; próximos marcos permanecem sujeitos aos próprios gates do plano canônico.**
