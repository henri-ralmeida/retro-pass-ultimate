# Caixas 3D e artes locais

O protótipo sem emulação usa embalagens originais quando disponíveis. Isso não significa criar capas fictícias. Nenhuma ROM é necessária.

O botão **Escanear jogos** é a entrada para construir o catálogo a partir de uma pasta escolhida pelo usuário. A leitura é local, sem executar jogos nem modificar a coleção. Mídias já associadas em `gamelist.xml` podem preencher as faces. A consulta online ScreenScraper é uma etapa independente e deve indicar explicitamente quando não estiver configurada.

O manifesto padrão é `assets/local_box_art/manifest.json`. Esse diretório é ignorado pelo Git. Também pode ser indicado por `RETROPASS_BOX_ART_MANIFEST`. Caminhos de imagens relativos são resolvidos junto ao manifesto.

Exemplo de estrutura:

```json
{"items":[{"id":"wonder_boy","title":"Wonder Boy","subtitle":"MASTER SYSTEM","cover_front":"wonder_boy_front.png","cover_spine":"wonder_boy_spine.png","cover_back":"wonder_boy_back.png"}]}
```

Campos opcionais `cartridge_label` e `cartridge_top` associam separadamente a frente e o topo do cartucho. `wheel` exibe o logo local da própria entrada no lugar do título tipográfico, preservando proporção e transparência. Se faltar ou falhar a leitura, o título normal continua legível; não se reutiliza logo de outro jogo. O scanner aceita esses nomes explícitos em `gamelist.xml` e também `marquee` como wheel. Nenhuma capa é reutilizada automaticamente como label.

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

## Residência e qualidade em runtime

O menu mantém no máximo três cards e cinco caixas 3D, independentemente da quantidade de metadados. Texturas locais usam cache por caminho/revisão e LOD: até 2048 pixels para a seleção e 512 para vizinhos. Arquivos fonte não são alterados. Cabeçalhos PNG/JPEG/WebP e dimensões são verificados antes da decodificação; o cache retém até 24 texturas e 192 MiB estimados. Esses limites não representam o total de memória do motor, materiais, decoder ou driver.

O sorteio inicial considera entradas válidas do catálogo e permanece estável durante foco, layout, inspeção e retorno. Escolha explícita pelo usuário prevalece. Uma nova visita explicitamente iniciada evita repetir imediatamente o último ID quando há alternativas, dentro da mesma execução; não há promessa de histórico de sorteios entre reinicializações. Versões/arquivos distintos continuam entradas distintas, sem inferir que sejam o mesmo lançamento. Testes com mil metadados sintéticos não representam o inventário pessoal do usuário.

### Inventário de metadados

`cosmic/catalog_import.gd` adapta um JSON de inventário explicitamente fornecido, sem ler ROMs, diretórios ou mídia. O grupo padrão é Master System; Mark III é uma chamada separada. IDs internos derivam de sistema+caminho relativo, preservando variantes que compartilham um ID ScreenScraper. Registros ausentes permanecem consultáveis, mas não entram no sorteio. Sem raiz local configurada, associações de mídia permanecem somente metadados: não são tratadas como imagens presentes nesta máquina.

A seleção inicial sorteia somente candidatos elegíveis e permanece estável durante foco, redesenho, inspeção e retorno. Uma nova visita explícita evita repetir imediatamente o último registro quando há alternativas. Não há promessa de uniformidade perceptível em poucas escolhas nem sincronização persistente entre execuções.
