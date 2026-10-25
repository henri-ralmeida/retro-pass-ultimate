# Validação da revisão de catálogo e caixas originais

## Executado na nuvem

Godot 4.6.3, Compatibility, Linux. Importação e suíte `tools/verify_project.sh` concluídas com código 0, sem erro ou aviso no log final.

- 1.661 verificações funcionais: seleção, história, inspeção, foco, controles, biblioteca, catálogo e scanner.
- 86.683 verificações de stress de zoom do console aprovado, em 5.412 estados geométricos e 4.045 eventos sintéticos.
- Scanner: fixtures temporários, arquivos falsos identificados como QA; nenhum jogo executado, nenhum arquivo do PC do usuário acessado.
- XML malformado/DTD, duplicação, ausência de faces, cancelamento, limites de percurso e links simbólicos cobertos.
- Cache escrito somente após leitura explícita bem-sucedida; cancelamento preserva catálogo anterior.
- Geometria da caixa original, articulação de tampa/cartucho, faces independentes e enquadramento cobertos.

## Limites

Teste headless não substitui imagem real nem controle físico. O seletor nativo Windows ainda não foi testado em Windows. Caminhos com capitalização divergente no gamelist são tratados conservadoramente como não associados. O serviço ScreenScraper autenticado não foi acessado e a obtenção online permanece não configurada. As imagens comerciais locais não são publicadas no repositório.

A capa Wonder Boy disponível tem resolução de origem limitada; ampliar a imagem não cria detalhes novos. Alex Kidd não recebeu capa inventada nem edição presumida.

Na verificação de checkout limpo, as capas vetoriais fictícias antigas causaram encerramento por limite de memória da nuvem durante a importação. Como já não participam do aplicativo, a pasta histórica recebeu `.gdignore`, preservando os fontes e excluindo apenas sua importação desnecessária.
