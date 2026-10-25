# Manual integrado: páginas locais

O leitor é uma interface de imagens locais, sem emulação, download automático ou leitor externo. Não há páginas reais de manual incluídas neste projeto. A ausência de mídia permanece explícita; páginas de outro jogo não são utilizadas como substitutas.

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
- Cache limitado a 3 páginas e 64 MiB de texturas estimadas; overhead do driver/GPU é adicional.
- Zoom de 1× a 4×. A ampliação não recupera detalhe inexistente na digitalização.
- PDF não é decodificado nesta etapa. Um campo `manual_pdf` sem páginas de imagem é informado como não suportado.
- Os originais não são regravados, reduzidos ou publicados.

## Procedência

O manifesto e as páginas pertencem à configuração local do usuário. Não adicione digitalizações comerciais, segredos ou arquivos pessoais ao repositório público sem autorização e avaliação da procedência. A fixture de QA é explicitamente sintética e não representa manual de nenhum jogo.
