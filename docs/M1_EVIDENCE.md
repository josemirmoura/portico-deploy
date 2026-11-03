# M1 | Evidências e bloqueadores para aceite

**Registro:** 03/11/2026. **Estado: PARCIAL, NÃO HOMOLOGADO.**

## Evidência verificável de CI

- Revisões de implementação: `02e125c7058c8ccb58117c3cce95502efa33bbe0` e `96858e9313807e081878fe48566d921c56bbe1bb` (workflow por PR).
- [GitHub Actions CI PASS (HTTP/segurança)](https://github.com/josemirmoura/portico-deploy/actions/runs/41724328760) e [CI PASS (PR staging e aplicação com verificação)](https://github.com/josemirmoura/portico-deploy/actions/runs/41724918097).
- 17 testes Python aprovados: pacote TAR regular/aninhado, rejeição de traversal, caminhos absolutos, hardlinks/symlinks, duplicados, tamanhos e número de entradas acima do limite, recuperação diante de pacote corrompido, prevenção de replay, validação de link ativo, primeira publicação e rollback.
- Teste HTTP efêmero com servidor `127.0.0.1`: publicação v1 → leitura HTTP 200 → atualização v2 → leitura HTTP 200 → rollback v1 → leitura correta por HTTP.
- 4 verificações shell aprovadas: plano sem alterações, recusa branch sem proteção, simulação de PR + aplicação do workflow aprovado com mocks, teste negativo de checksum antes de criação de conta.
- Binários GitHub Actions pinados por SHA nas duas workflows; sem execução de PR no runner próprio.

## Segurança comprovada apenas nestes testes

- Verificações locais recusam caminhos TAR perigosos e metadados não permitidos.
- `--apply` não prossegue sem repositório privado e branch padrão `main` protegida/verificável.
- Workflow staging ocorre via PR e sem SSH. O bootstrap recusa um workflow inexistente ou divergente na main antes de qualquer chamada SSH ao host.
- Digest inválido do runner impede criação de usuário, comprovado com mock em runner descartável GitHub-hosted.
- O workflow de app permite disparo manual e exige opt-in (`PD_AUTO_DEPLOY=true`) para deploy por push.
- Healthcheck opcional `PD_HEALTH_URL` faz rollback em falha. **O caminho de healthcheck via runner real ainda não foi testado**.

## Pendências que bloqueiam M1

1. **E2E REAL em Linux descartável com repositório PRIVADO de teste**: credencial administrativa para registro de runner, workflow publicado no GitHub, runner online, download/upload de artefato, primeira implantação e upgrade por `workflow_dispatch`, health real e rollback demonstrado no destino. Simulações locais e CI não substituem essa prova.
2. **Revisão de isolamento do runner**: sem sudo/docker.sock, separação real de contas/diretórios, controle de quem edita workflows, atualização e revogação; registrar teste negativo cruzado entre projetos.
3. **Fluxo protegido: implementação entregue, E2E real pendente.** `--stage` cria PR, não toca servidor; `--apply` verifica igualdade exata do workflow na `main` antes de SSH. Simulação aprovada [CI 41724918097](https://github.com/josemirmoura/portico-deploy/actions/runs/41724918097). Falta ensaio de criação/merge de PR em repositório privado descartável.
4. **Recuperação/desinstalação**: procedimento de desregistro do runner e parada do serviço, sem apagar aplicações ou dados. A aplicação do instalador ainda não é transacional entre GitHub e host.
5. **Aceite HTTP**: provar que o healthcheck corresponde à release atual (resposta 200 isolada pode identificar conteúdo anterior), registrar resultados no SHA e inventário/reversão.
6. Corrigir quaisquer falhas identificadas nesses ensaios, obter CI no SHA final e atualizar docs/issue #1/#2.

## Limites de autoridade

**Nenhuma execução de setup --apply, reboot, deploy, alteração de configuração ou instalação no SRV-IA ou VPS foi realizada neste trabalho.** O ParecIA mantém seu CI/CD independente e não foi migrado. Ambiente do teste HTTP: runner efêmero do GitHub, com serviço local sintético.

**Decisão:** M1 continua ativo. M2, M3 e M4 ficam bloqueados até que as pendências e os testes E2E reais sejam concluídos.

## Nova etapa: laboratório Linux real de duas jobs (pendente de CI neste commit)

A workflow CI contém duas novas jobs `m1-disposable-host` e `m1-disposable-deploy`. A primeira constrói e envia artefato real via GitHub Actions; a segunda recebe o artefato em **outra VM efêmera**, cria conta Linux sem sudo/Docker, publica usando a implementação real, serve os arquivos por HTTP como `www-data`, verifica upgrade e rollback e destrói o laboratório. O teste deve ser comprovado pelo log e SHA da workflow após execução. **O laboratório não registra um self-hosted runner no GitHub**, portanto o gate de registro remoto do M1 continua pendente.

## Gate HTTP: revisão vinculada ao SHA

O workflow foi alterado para exigir `PD_SITE_URL` HTTPS com base pública; o engine inclui `portico-deploy-revision.txt` dentro da release; após o deploy o GitHub compara o conteúdo HTTP com o SHA esperado. Resposta 200 de versão antiga não é aceita. A ausência de URL ou incompatibilidade provoca rollback. **Aguardar CI no SHA desta alteração e E2E do workflow real em servidor de teste; não atribuir aceite antecipado.**
