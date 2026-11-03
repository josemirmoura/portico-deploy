# AGENTS.md | Pórtico Deploy

Repositório independente: josemirmoura/portico-deploy. Propósito: instalação de automação CI/CD para servidores Linux usando GitHub Actions e runners de privilégio mínimo.

## Regras de execução
1. Consultar README, docs/ARCHITECTURE.md e docs/SECURITY.md; examinar HEAD, issues, CI.
2. Preferir componentes existentes e padrões consolidados: GitHub Actions, gh CLI, SSH, systemd.
3. Não instalar nada na VPS/SRV-IA sem autorização específica do proprietário. Testes invasivos somente em ambiente descartável.
4. Preservar projetos existentes, nunca tocar em Community ou Infinity.
5. Repositórios que usam runner no host devem ser privados e ter controles fortes sobre quem altera workflows. Nunca disparar jobs de pull_request no runner de deploy.
6. Toda alteração requer teste, SHA, histórico, evidência e plano de rollback. Distinguir código escrito, CI verde, E2E e aceite humano.
7. Objetivo futuro: ChatGPT pode pedir deploy, status e rollback via integração autorizada. Não afirmar que uma interface de disparo de workflows já existe nesta conexão.
8. Nunca publicar release estável ou promover em produção sem UAT e GO do proprietário.

## Roadmap prioritário
P0: fluxo de release atômica em CI e runner isolado. P1: instalador integrado com validação e reversibilidade. P2: E2E descartável e UAT. P3: adaptadores Node/Python/Docker e comando MCP (somente após base segura).
