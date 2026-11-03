# Segurança e limites

1. O Pórtico Deploy é público; os repositórios de aplicação com runner no host precisam ser privados.
2. O instalador exige acesso administrativo pontual ao host. O runner criado depois NÃO recebe sudo, docker.sock ou direitos administrativos.
3. Alterações de workflows em main podem executar comandos arbitrários como o usuário do runner. Habilitar branch protection, revisão de PR e proteções de environment ANTES de permitir colaboradores externos.
4. Somente artefatos estáticos públicos são suportados: diretórios e arquivos de releases são legíveis por outras contas locais. Não colocar credenciais nos artefatos.
5. O pacote é extraído sem seguir symlinks, hardlinks, dispositivos ou trajetórias que escapem de staging. Há limites de tamanho e quantidade. Conteúdo implantado pode ainda ser perigoso para o serviço que o serve; revisar os builds.
6. Identidades SSH de bootstrap e tokens de registro de runner não são guardados no repositório. Token GitHub de runner é curto e usado somente na configuração.
7. Revogar runner em GitHub e parar serviço no host em caso de suspeita. A remoção de releases e projetos só ocorre em procedimento separado, com inventário e confirmação.
8. Fluxo de dados e binários oficiais da GitHub Runner requer SHA-256 válido. Se a API não retornar digest verificável, instalação deve falhar fechada.
9. Nenhum deploy real, alteração de firewall, proxy ou Docker está autorizado como efeito colateral da configuração deste repositório.

Referência oficial: https://docs.github.com/en/actions/reference/security/secure-use
