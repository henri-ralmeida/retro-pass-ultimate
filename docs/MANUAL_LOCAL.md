# Manual integrado: páginas locais

O leitor apresenta um livreto 3D com páginas locais, sem emulação, download automático ou leitor externo. Não há páginas reais de manual incluídas neste projeto. A ausência de mídia permanece explícita; páginas de outro jogo não são utilizadas como substitutas.

## Vincular páginas ao item correto

No manifesto local da coleção, a entrada do jogo pode fornecer `manual_pages`, em ordem de leitura. Caminhos relativos são resolvidos junto ao próprio manifesto. São aceitos PNG e JPEG locais; URLs, compartilhamentos de rede e caminhos com travessia `..` são recusados.

Exemplo de campos, não uma coleção fornecida:

```json
{
  "id": "identificador_do_seu_item",
  "title": "Título do item",
  "manual_item_id": "identificador_do_seu_item",
  "manual_pages": [
    "manual/pagina-001.png",
    "manual/pagina-002.png"
  ]
}
```

Se `manual_item_id` ou `manual_game_id` estiver declarado, precisa corresponder exatamente a `id`. Essa conferência verifica o vínculo do catálogo, não autentica visualmente o conteúdo, a região ou a edição das digitalizações. Confira essas informações ao preparar sua coleção.

## Controles e limites

O leitor mantém navegação por páginas, zoom, deslocamento da página ampliada, ajuste à tela e Voltar. Eventos são consumidos pelo leitor: navegar nele não deve trocar o jogo nem girar a caixa ao fundo. A perda de foco cancela o arraste sem apagar a página.

- Até 128 páginas, cada uma com até 8 MiB codificados.
- Dimensões até 4096×4096, verificadas antes da decodificação.
- Cache limitado por estado: até seis texturas/24 MiB no livro e duas/64 MiB no zoom. Overhead do driver/GPU e decodificação é adicional.
- Zoom de 1× a 4×. A ampliação não recupera detalhe inexistente na digitalização.
- PDF não é decodificado nesta etapa. Um campo `manual_pdf` sem páginas de imagem é informado como não suportado.
- Os originais não são regravados, reduzidos ou publicados.

## Procedência

O manifesto e as páginas pertencem à configuração local do usuário. Não adicione digitalizações comerciais, segredos ou arquivos pessoais ao repositório público sem autorização e avaliação da procedência. A fixture de QA é explicitamente sintética e não representa manual de nenhum jogo.

## Procedência e validação atual

O leitor foi validado também com um manual original de Wonder Boy fornecido privadamente: 32 páginas digitalizadas, inglês, edição US com copyright Sega of America de 1987 e garantia US. A revisão exata de impressão não foi inferida pelo nome da ROM. As imagens JPEG originais de 1039 × 1455 pixels foram extraídas sem recompressão, preservando páginas em branco e ordem. A capa, miolo, garantia e verso foram conferidos no Godot real em 16:9 e 4:3; o texto pequeno precisa de zoom e mantém o grão do escaneamento.

Esse teste comprova entrada local → associação → leitura. Não comprova coleta online automática: o PDF foi transferido com autorização e convertido fora do aplicativo. PDF e páginas permanecem privados e não acompanham o código público. Não há credenciais ScreenScraper configuradas neste protótipo.

A compatibilidade de ações com o RetroBat é documentada em [CONTROLES_MANUAL_RETROBAT.md](CONTROLES_MANUAL_RETROBAT.md). O modelo de livreto e sua animação são recursos próprios, sujeitos a validação visual independente.

## Livreto 3D e leitura ampliada

A caixa original pode receber um livreto canônico com a primeira página real sob suas presilhas. O vínculo explícito `manual_item_id` ou `manual_game_id` deve coincidir com o item. O encaixe deriva das malhas existentes, conserva a proporção completa da página e recusa espessura acima do vão. A espessura padrão de 0,8 mm é demonstrativa, não uma medição do impresso original; o vão modelado é aproximadamente 1 mm.

Antes da aproximação, o próprio livreto da caixa percorre uma liberação reversível: a área livre do papel curva, desliza para sair das presilhas fixas, sobe e volta a ficar plana. O perfil é conservador e demonstrativo, não uma simulação de material nem uma medição OEM; a configuração é recusada se os volumes varridos conservadores colidirem com os limites derivados das malhas da caixa. Quando o zoom da caixa não deixa espaço para a retirada, a câmera recua suavemente e recupera o enquadramento anterior na devolução. Essa preparação pausa com perda de foco e pode ser cancelada. O endpoint também deve ficar inteiro na viewport e sem sobreposição projetada com o cartucho, pois os dois mundos 3D não compartilham profundidade. Só depois desse percurso um proxy da mesma geometria/capa/dimensões faz a aproximação projetada entre viewports. O retorno executa as etapas inversas e restaura exatamente os recursos originais do livreto. Cancelamento, perda de foco e fechamento da biblioteca não movem as presilhas. Cada folha tem duas faces; a navegação por teclado/controle alcança cada face, inclusive versos e páginas em branco. A abertura do livro, virada reversível e pausa ao perder foco não alteram a caixa. Movimento reduzido elimina a transição animada.

No 3D, o cache retém no máximo seis páginas e 24 MiB estimados, com lado de textura limitado a 1024 pixels. O modo de leitura ampliada permanece no mesmo mundo e nas mesmas malhas 3D. A câmera aproxima e desloca a face selecionada; só essa face recebe LOD de leitura até 3072 pixels, preservando a resolução nativa dos scans menores. No máximo duas texturas/64 MiB ficam nesse estado, com descarte do LOD alto ao retornar. Fontes não são regravadas ou aumentadas artificialmente. Memória do driver, viewport, malhas e picos temporários de decodificação não estão incluídos nesses limites de cache.

Confirmar entra no zoom do próprio livro 3D; Confirmar ou Voltar retorna à mesma face/enquadramento do livro, sem interface 2D. Voltar no livro devolve-o à caixa. Os ombros/direções seguem os dois estados documentados na referência RetroBat. Mouse, inclinação do livro e animação de folhas são extensões deste protótipo.
