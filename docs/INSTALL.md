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
4. Autorize conscientemente: bash scripts/setup.sh --repo OWNER/PRIVATE-APP --project app1 --host admin@host --apply
5. Coloque artefatos estáticos em public/ do repositório de aplicação. Configure servidor web existente para apontar para /opt/portico-deploy/apps/app1/current.
6. Dispare: gh workflow run portico-deploy.yml -R OWNER/PRIVATE-APP --ref main
7. Confira status/steps/health externo e links atuais antes de considerar implantado.

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

O segundo comando exige confirmação geral e autorização por projeto. O instalador não aplica mudanças irreversíveis sem passar por essas etapas. MVP: um repositório por destino; múltiplos ambientes para o mesmo repositório exigem evolução do workflow.
