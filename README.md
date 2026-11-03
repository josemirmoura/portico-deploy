# Pórtico Deploy 🚀

Deploy de aplicações Linux com GitHub Actions, permissões mínimas e operações auditáveis.

> **Pré-lançamento experimental (MVP 0.1).** Não executamos instalação ou deploy em SRV-IA/VPS durante a criação deste repositório. Os testes de CI são efêmeros e não comprovam uma implantação real.

## Objetivo

Uma configuração inicial orientada pelo proprietário, depois: GitHub → testes → pacote → runner isolado → release atômico → verificação → rollback. O produto é independente de Pórtico Community e Infinity.

### Primeiro adaptador: sites estáticos

O MVP publica o conteúdo de um diretório de artefatos (por padrão, public/) como nova release em /opt/portico-deploy/apps/PROJETO/releases/SHA, atualiza o link current atomicamente e mantém previous para rollback. Não instala proxy, não abre portas e não manipula Docker. Projetos Python, Node e Docker precisam de adaptadores futuros; não usar este fluxo para publicar o ParecIA sem adaptação.

## Instalação planejada

Executar a partir de um computador administrador com bash, gh, ssh, curl, python3 e acesso SSH administrativo previamente configurado.

1. Clonar e revisar este repositório em um commit fixo.
2. Executar: bash scripts/setup.sh --repo DONO/APLICACAO --project meu-site --host usuario@servidor --runner-label pd-meu-site --plan
3. Revisar o plano, requisitos de runner/infra e fronteiras de segurança.
4. Executar o mesmo comando substituindo --plan por --apply, após autorização do proprietário.

A implantação requer que DONO/APLICACAO seja **privado**; este repositório de código do Pórtico pode ser público. O setup não desativa regras de proteção do GitHub. Workflow de publicação é manual por padrão e inclui opção de auto deploy após configuração explícita de PD_AUTO_DEPLOY=true pelo proprietário. A aprovação de ambiente GitHub é recomendada.

## Operação

- No repositório da aplicação: gh workflow run portico-deploy.yml -R DONO/APLICACAO --ref main
- Acompanhar: gh run list -R DONO/APLICACAO --workflow portico-deploy.yml
- O acionamento por comando de ChatGPT depende da integração de ferramentas com capacidade de disparar workflow ou publicar uma solicitação autenticada. Não está disponível automaticamente nesta edição.
- A disponibilidade HTTPS pública também depende de proxy, DNS, TLS e de serviço que sirva a pasta current, que ficam fora deste MVP.

## Princípios

- Runner de cada aplicativo: usuário próprio, sem sudo, sem grupo docker, diretório de aplicação exclusivo.
- Código de publicação root-owned, com verificação do SHA e validação de arquivos.
- Build no runner hospedado pelo GitHub; runner privado apenas recebe artefato e executa operação fixa.
- Nunca aceitar PRs de origem não confiável em um runner com privilégios no host.
- Sem segredos em commits, logs ou parâmetros de comando.
- Nenhuma alteração em Community/Infinity, VPS ou SRV-IA sem ação explícita e verificável do proprietário.

Veja docs/ARCHITECTURE.md, docs/SECURITY.md e AGENTS.md.
