# Caixas 3D e artes locais

O protótipo sem emulação usa embalagens originais quando disponíveis. Isso não significa criar capas fictícias. Nenhuma ROM é necessária.

O botão **Escanear jogos** é a entrada para construir o catálogo a partir de uma pasta escolhida pelo usuário. A leitura é local, sem executar jogos nem modificar a coleção. Mídias já associadas em `gamelist.xml` podem preencher as faces. A consulta online ScreenScraper é uma etapa independente e deve indicar explicitamente quando não estiver configurada.

O manifesto padrão é `assets/local_box_art/manifest.json`. Esse diretório é ignorado pelo Git. Também pode ser indicado por `RETROPASS_BOX_ART_MANIFEST`. Caminhos de imagens relativos são resolvidos junto ao manifesto.

Exemplo de estrutura:

```json
{"items":[{"id":"wonder_boy","title":"Wonder Boy","subtitle":"MASTER SYSTEM","cover_front":"wonder_boy_front.png","cover_spine":"wonder_boy_spine.png","cover_back":"wonder_boy_back.png"}]}
```

Use imagens da mesma edição. Uma frente de uma edição não deve ser combinada silenciosamente com lombada/verso de outra. Faces ausentes não são reconstruídas como se fossem originais.

## Prévia de desenvolvimento

A base anterior contém um scan completo Wonder Boy de 1200 × 761 pixels, com embalagem em inglês, SEGA of America, “The Mega Cartridge”, ©1987 e código de barras 010086050684. O scan evidencia a embalagem norte-americana; sua origem específica no ScreenScraper não foi verificada. A resolução original é um limite real do zoom, sem promessa de detalhe infinito.

Recortes: verso 544 × 761, lombada 101 × 761, frente 555 × 761. Não há arte Alex Kidd confirmada no material disponível. Não duplicamos Wonder Boy para simular um catálogo maior.

O material foi reutilizado somente na prévia local autorizada. Não foi encontrada evidência de licença de redistribuição pública junto aos arquivos. Isso não é uma conclusão jurídica sobre seu uso; significa que a publicação desses arquivos é uma decisão separada da implementação e da prévia. Marcas e artes pertencem aos respectivos titulares.

A geometria reaproveitada da caixa antiga conserva tampa separada e estrutura tridimensional. A procedência específica da malha e das imagens é registrada com os assets locais; nenhum arquivo do projeto antigo é sobrescrito.

## Integração online

A documentação oficial da API v2 exige identificação própria do aplicativo (`devid`, `devpassword`, `softname`), além das condições de identificação dos jogos. Conta de usuário e quotas podem influenciar acesso. Não extraímos credenciais de RetroBat ou de outro aplicativo; não armazenamos segredos no repositório.

Documentação: https://www.screenscraper.fr/webapi2.php

Nesta revisão, o fluxo online autenticado não foi validado. O uso de imagens locais e testes simulados não comprova acesso ao serviço. Arquivos ROM não são enviados; qualquer futura consulta deve limitar dados à identificação necessária do jogo, com configuração e autorização apropriadas.
