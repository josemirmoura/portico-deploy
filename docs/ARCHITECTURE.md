# Pórtico Deploy | Arquitetura do MVP

Fluxo:
- Administrador autenticado via gh e SSH executa setup com confirmação.
- O setup registra runner GitHub isolado no repositório PRIVADO da aplicação e instala workflow portico-deploy.yml.
- Build roda em ubuntu-latest (GitHub-hosted); gera pacote site.tgz de public/.
- Job de deploy só roda para main e mediante workflow_dispatch (ou push se PD_AUTO_DEPLOY=true).
- Job usa runner dedicado pd-PROJETO, faz download do pacote (sem checkout do repositório) e chama release.py em caminho root-owned.
- release.py extrai somente arquivos regulares/diretórios dentro de novo staging, coloca release imutável e troca current por link atômico.
- Link previous aponta para versão anterior e rollback pode ser executado manualmente pelo operador autorizado.

Limites:
- Primeiro adaptador publica arquivos estáticos. É necessário que o servidor HTTP existente aponte para current.
- Não provisiona reverse proxy, certificado, containers, banco de dados, DNS ou WireGuard.
- SRV-IA sem IP público é suportado por runner que inicia conexão de saída com GitHub.
- Runner GitHub é código de terceiros executando no host; isolar por conta, sem sudo nem Docker e nunca usar em repositório público de aplicação.
- Configuração de proteção da main e environment production é de responsabilidade do operador até termos automação validada.
- Auditoria inicial é o histórico de runs do GitHub e trilha local append-only; trilha local não é tamper-proof para o próprio usuário de deploy.

Estado: proposta técnica implementada parcialmente; provas E2E e proteção de ambiente pendentes.
