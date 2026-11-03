# M1 | Evidências e bloqueadores para aceite

**Registro:** 03/11/2026. **Estado: PARCIAL, NÃO HOMOLOGADO.**

## Evidência verificável de CI

- Revisão de implementação: `02e125c7058c8ccb58117c3cce95502efa33bbe0`.
- [GitHub Actions CI PASS](https://github.com/josemirmoura/portico-deploy/actions/runs/41724328760).
- 17 testes Python aprovados: pacote TAR regular/aninhado, rejeição de traversal, caminhos absolutos, hardlinks/symlinks, duplicados, tamanhos e número de entradas acima do limite, recuperação diante de pacote corrompido, prevenção de replay, validação de link ativo, primeira publicação e rollback.
- Teste HTTP efêmero com servidor `127.0.0.1`: publicação v1 → leitura HTTP 200 → atualização v2 → leitura HTTP 200 → rollback v1 → leitura correta por HTTP.
- 4 verificações shell aprovadas: plano sem alterações, recusa branch sem proteção, simulação de workflow + instalação via mocks, teste negativo de checksum antes de criação de conta.
- Binários GitHub Actions pinados por SHA nas duas workflows; sem execução de PR no runner próprio.

## Segurança comprovada apenas nestes testes

- Verificações locais recusam caminhos TAR perigosos e metadados não permitidos.
- `--apply` não prossegue sem repositório privado e branch padrão `main` protegida/verificável.
- Erro ao criar o workflow GitHub interrompe o bootstrap antes de qualquer chamada SSH ao host.
- Digest inválido do runner impede criação de usuário, comprovado com mock em runner descartável GitHub-hosted.
- O workflow de app permite disparo manual e exige opt-in (`PD_AUTO_DEPLOY=true`) para deploy por push.
- Healthcheck opcional `PD_HEALTH_URL` faz rollback em falha. **O caminho de healthcheck via runner real ainda não foi testado**.

## Pendências que bloqueiam M1

1. **E2E REAL em Linux descartável com repositório PRIVADO de teste**: credencial administrativa para registro de runner, workflow publicado no GitHub, runner online, download/upload de artefato, primeira implantação e upgrade por `workflow_dispatch`, health real e rollback demonstrado no destino. Simulações locais e CI não substituem essa prova.
2. **Revisão de isolamento do runner**: sem sudo/docker.sock, separação real de contas/diretórios, controle de quem edita workflows, atualização e revogação; registrar teste negativo cruzado entre projetos.
3. **Fluxo de instalação sob branch protegida**: quando commit direto em `main` é recusado, preparar workflow via PR e prosseguir com bootstrap após merge, sem deixar instalação parcial.
4. **Recuperação/desinstalação**: procedimento de desregistro do runner e parada do serviço, sem apagar aplicações ou dados. A aplicação do instalador ainda não é transacional entre GitHub e host.
5. **Aceite HTTP**: provar que o healthcheck corresponde à release atual (resposta 200 isolada pode identificar conteúdo anterior), registrar resultados no SHA e inventário/reversão.
6. Corrigir quaisquer falhas identificadas nesses ensaios, obter CI no SHA final e atualizar docs/issue #1/#2.

## Limites de autoridade

**Nenhuma execução de setup --apply, reboot, deploy, alteração de configuração ou instalação no SRV-IA ou VPS foi realizada neste trabalho.** O ParecIA mantém seu CI/CD independente e não foi migrado. Ambiente do teste HTTP: runner efêmero do GitHub, com serviço local sintético.

**Decisão:** M1 continua ativo. M2, M3 e M4 ficam bloqueados até que as pendências e os testes E2E reais sejam concluídos.
