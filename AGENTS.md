# AGENTS.md | Pórtico Deploy

Repositório independente: josemirmoura/portico-deploy. Propósito: instalação de automação CI/CD para servidores Linux usando GitHub Actions e runners de privilégio mínimo.

## Regras de execução
1. Ler **docs/EXECUTION_PLAN.md** (plano canônico), README, docs/ARCHITECTURE.md e docs/SECURITY.md; examinar HEAD, issues, CI.
2. Preferir componentes existentes e padrões consolidados: GitHub Actions, gh CLI, SSH, systemd.
3. Não instalar nada na VPS/SRV-IA sem autorização específica do proprietário. Testes invasivos somente em ambiente descartável.
4. Preservar projetos existentes, nunca tocar em Community ou Infinity.
5. Repositórios que usam runner no host devem ser privados e ter controles fortes sobre quem altera workflows. Nunca disparar jobs de pull_request no runner de deploy.
6. Toda alteração requer teste, SHA, histórico, evidência e plano de rollback. Distinguir código escrito, CI verde, E2E e aceite humano.
7. Objetivo futuro: ChatGPT pode pedir deploy, status e rollback via integração autorizada. Não afirmar que uma interface de disparo de workflows já existe nesta conexão.
8. Nunca publicar release estável ou promover em produção sem UAT e GO do proprietário.

## Marcos obrigatórios
M0: base experimental entregue (CI, não E2E). M1: deploy estático seguro em ambiente efêmero. M2: cadastro reutilizável servidor/aplicação. M3: comando autenticado de deploy pela IA. M4: adaptador de serviço e destinos múltiplos. M5: UAT e GO/NO-GO.

**Fonte de verdade para ordem, escopo, gates e limites: [docs/EXECUTION_PLAN.md](docs/EXECUTION_PLAN.md).** Somente um marco ativo por vez. É proibido desviar para painéis, SaaS, Kubernetes ou novos agentes sem necessidade demonstrada.
