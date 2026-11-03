# Instalação e aceite inicial

## Pré-requisitos
- Repositório **privado** de aplicação, com diretório public/ contendo arquivos estáticos.
- Máquina administrativa Linux com gh CLI autenticado como administrador do repositório e SSH com chave de host confiável.
- SRV-IA ou VPS Linux x86_64 com systemd, curl, tar, python3, sha256sum, sudo e saída HTTPS para github.com.
- Conta SSH de bootstrap autorizada a executar sudo -n durante a instalação; após setup o runner tem usuário próprio sem sudo.
- Rede do servidor permite saída para serviços GitHub Actions. Nenhum ingresso público no SRV-IA é necessário.
- Operador deve proteger a branch main, restringir autores de workflow e configurar environment production com revisão quando aplicável.

## Uso

1. Clone com Git: git clone https://github.com/josemirmoura/portico-deploy.git
2. Revise o código e fixe um commit ou tag de confiança.
3. Planeje: bash scripts/setup.sh --repo OWNER/PRIVATE-APP --project app1 --host admin@host --plan
4. Abra PR do workflow: bash scripts/setup.sh --repo OWNER/PRIVATE-APP --project app1 --host admin@host --stage
5. Revise/merge a PR na main protegida.
6. Autorize conscientemente o provisionamento: bash scripts/setup.sh --repo OWNER/PRIVATE-APP --project app1 --host admin@host --apply
7. Coloque artefatos estáticos em public/ do repositório de aplicação. Configure servidor web existente para apontar para /opt/portico-deploy/apps/app1/current.
8. Dispare: gh workflow run portico-deploy.yml -R OWNER/PRIVATE-APP --ref main
9. Confira status/steps/health externo e links atuais antes de considerar implantado.

Por padrão, o gatilho push executa build/teste do pacote, mas não envia deploy. Para ativar CD em push, configure a variável do repositório PD_AUTO_DEPLOY=true depois de UAT. Revogar/excluir runner pelo GitHub e parar o serviço no host caso haja suspeita; não excluir dados de projetos automaticamente.

### Limitações iniciais
- Usuário do runner não pode alterar configuração do proxy, systemd global ou containers.
- Não há healthcheck de serviço, apenas integridade do pacote e atualização atômica. Operador deve validar HTTP fora do workflow.
- As releases de arquivos estáticos são legíveis por usuários locais, para permitir que o servidor web existente as sirva. Nunca coloque segredos no diretório de artefatos.
- Implantação de aplicativos não estáticos requer adaptadores posteriores.
- Não há rollback acionável via GitHub Actions nesta versão; somente função local segura implementada e testada.
- O setup não é transacional entre host e GitHub: se a segunda etapa falhar, pode restar runner registrado e exigirá reconciliação.
- Sem testes E2E em host real: a instalação precisa de UAT e autorização do operador.

## Vários servidores com um comando

Prepare arquivo TSV com projeto, repositório privado, host SSH e diretório de artefatos (veja examples/fleet.tsv). Execute:

    bash scripts/setup-fleet.sh --file minha-frota.tsv --plan
    bash scripts/setup-fleet.sh --file minha-frota.tsv --apply

O segundo comando exige confirmação geral e autorização por projeto; **antes**, execute --stage e incorpore os PRs de todos os projetos. O instalador não aplica mudanças irreversíveis sem passar por essas etapas. MVP: um repositório por destino; múltiplos ambientes para o mesmo repositório exigem evolução do workflow.

## Bloqueio de inicialização insegura

O modo --apply exige branch padrão main protegida no GitHub e falha fechado se a proteção não estiver configurada ou a credencial gh não conseguir consultá-la. Configure as regras de revisão de alteração em workflows antes de aprovar novos runners.

## Verificação de saúde

O workflow exige a variável GitHub `PD_SITE_URL`, com a **URL base pública HTTPS** que serve `current/`. O motor escreve o arquivo `portico-deploy-revision.txt` com o SHA da release e o workflow exige que `PD_SITE_URL/portico-deploy-revision.txt` corresponda exatamente ao commit publicado. Resposta HTTP 200 de versão antiga é considerada falha e provoca rollback automático; sem URL segura também ocorre rollback com job FAIL. Não utilizar URLs de administração, IPs privados nem segredos. Validar HTTPS e roteamento antes do deploy.

## Ordem segura de configuração

O instalador abre PR via --stage e não toca no servidor. --apply só opera após o workflow exato aparecer na main protegida. Se a PR for recusada, nenhum host será alterado. Se o bootstrap do runner falhar após a criação do workflow, a variável PD_AUTO_DEPLOY permanece desativada, mas a reconciliação ainda é manual neste MVP. Não execute --apply às cegas em repositórios operacionais.

## Configuração via PR de segurança (M1)

Para respeitar políticas que exigem revisão na branch `main`, agora existem dois comandos separados:

1. `bash scripts/setup.sh --repo OWNER/PRIVATE-APP --project app1 --host admin@host --stage`: cria uma branch e PR com o workflow, sem conectar ao servidor. Revise e faça merge obedecendo às proteções do repositório.
2. `bash scripts/setup.sh --repo OWNER/PRIVATE-APP --project app1 --host admin@host --apply`: verifica se o workflow aprovado na `main` corresponde **exatamente** ao template e só então inicia o bootstrap do runner via SSH.

O `--plan` permanece sem efeitos. Mudanças manuais no workflow exigirâo reconciliação antes de `--apply` por segurança. `--stage` usa uma branch determinística por projeto e para em caso de conflito; não força branches existentes. Não tentar usar `--apply` em um repositório sem o PR previamente incorporado. O passo de merge é um gate humano de revisão, mesmo se o restante da configuração for automatizado.
