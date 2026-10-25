# Referência de controles do manual

Pesquisa do código oficial RetroBat, não execução de seu aplicativo nem teste de controle físico. Referência: EmulationStation master `37d70f3e46282ba431a64813347cf5b0431bbbfb` (23/10/2026), com o mesmo `GuiImageViewer.cpp` de `retrobat-8.3` em `45f37fd74819ee07118ca2e7680a907b25733ac5`.

O PDF usa `GuiImageViewer` e `ZoomableImageComponent`, não uma classe `GuiPdfViewer`. No Windows, `INVERTEDINPUTCONFIG` faz o perfil distribuído usar X para confirmar e Z para voltar. Remapeamentos pessoais e a opção InvertButtons podem mudar isso.

| Estado | Ação | Xbox / PlayStation / teclado padrão Windows |
|---|---|---|
| Páginas | Entrar no zoom | A / × / X |
| Páginas | Fechar leitor | B / ○ / Z |
| Páginas | Anterior / seguinte | LB / L1 / PageUp; RB / R1 / PageDown |
| Páginas | Anterior / seguinte | Direções: esquerda ou cima; direita ou baixo |
| Zoom | Reduzir / ampliar continuamente | LB / L1 / PageUp; RB / R1 / PageDown |
| Zoom | Mover região visível | D-pad ou analógico esquerdo |
| Zoom | Voltar à mesma página | Confirmar ou voltar |

O leitor oficial não possui reset dedicado, rotação, analógico direito nem LT/RT para estas ações. Sair e reentrar no zoom cria um enquadramento novo. O livro 3D, virada animada e alternância de apresentação do RETRO PASS ULTIMATE são recursos próprios, não reproduções prometidas do RetroBat. Limites de zoom/cache do protótipo também podem diferir por segurança e orçamento de memória.

Fontes fixadas:
- [Abertura de PDF e entrada do leitor](https://github.com/RetroBat-Official/emulationstation/blob/37d70f3e46282ba431a64813347cf5b0431bbbfb/es-app/src/guis/GuiImageViewer.cpp#L554-L685)
- [Zoom, pan e help](https://github.com/RetroBat-Official/emulationstation/blob/37d70f3e46282ba431a64813347cf5b0431bbbfb/es-app/src/guis/GuiImageViewer.cpp#L70-L188)
- [Grid de páginas](https://github.com/RetroBat-Official/emulationstation/blob/37d70f3e46282ba431a64813347cf5b0431bbbfb/es-core/src/components/ImageGridComponent.h#L518-L570)
- [Macro Windows](https://github.com/RetroBat-Official/emulationstation/blob/37d70f3e46282ba431a64813347cf5b0431bbbfb/es-core/src/InputConfig.h#L12-L14)
- [Teclado distribuído](https://github.com/RetroBat-Official/retrobat/blob/75313ef7a2c9dcaaf80ef580e2afadfe65913468/system/templates/emulationstation/es_input.cfg#L3-L21)
- [Mapeamento SDL](https://github.com/RetroBat-Official/emulationstation/blob/37d70f3e46282ba431a64813347cf5b0431bbbfb/es-core/src/InputManager.cpp#L965-L991)
