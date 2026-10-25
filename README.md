# RETRO PASS ULTIMATE

Protótipo desktop em Godot 4.6.3, inicialmente para Windows. A direção atual é **Sistemas no Infinito**: um Master System 3D em fundo cósmico, com inspeção interativa, história do console e entrada animada em uma biblioteca de caixas 3D. Substitui a proposta inicial de quarto 3D registrada no primeiro commit.

## Executar

1. Clone este repositório ou faça pull das atualizações.
2. Importe `project.godot` no Godot 4.6.3 e aguarde a importação dos recursos. Essa é a versão efetivamente testada; versões mais novas ainda precisam de validação. A fonte 4K é preservada e o atlas de runtime mantém os mesmos pixels 2K já usados anteriormente; veja [importação e identidade dos pixels](docs/IMPORTACAO_RECURSOS.md).
3. Pressione F5. O renderizador é Compatibility.

Este repositório contém código-fonte, não um executável Windows já validado. Blender não é necessário para executar.

## Interações

- X entra no sistema e Z volta no teclado. Enter/Espaço continuam como alternativas de confirmação.
- I / Inspecionar: manipulação 3D livre separada da história, tanto no console quanto na caixa. A caixa se aproxima fechada; arraste para escolher qualquer ângulo, sem giro automático nem presets de faces.
- X / Confirmar na caixa: aproxima, abre a tampa pela dobradiça e apresenta o mesmo cartucho. Z / Voltar recolhe o cartucho, fecha a caixa e retorna à coleção. Movimento reduzido aplica os estados sem transição.
- Manual, quando a caixa está apresentada: libera o mesmo livreto das presilhas e aproxima suas folhas 3D. Ombros/PgUp/PgDn viram folhas, direções escolhem a face, X amplia a leitura no próprio livro; roda/+− ajustam zoom e arraste desloca. Z sai da ampliação, depois devolve o livreto. Veja o mapa verificado em `docs/CONTROLES_MANUAL_RETROBAT.md`.
- Arraste para girar em dois eixos; roda ou +/− para zoom; setas também giram.
- R / Restaurar: orientação e zoom iniciais. Esc / Z / I / Voltar: sair.
- M: pausar/retomar movimento.
- Escanear jogos, na biblioteca: escolher uma pasta para catálogo local. Não executa arquivos, não altera a coleção e não faz consultas online sem integração configurada. Capas locais explicitamente associadas preenchem cada face disponível.
- Clique no controle3D P1/P2 para configurar seus comandos, ou use F1 → Master System → Jogador. O modelo e a lista textual selecionam a mesma ação. Veja [configuração contextual](docs/CONFIGURACAO_CONTROLE_3D.md).
- F1 / Controles, na tela do console: escolher família de símbolos e remapear teclas/botões; configuração persiste localmente. Conflitos trocam as duas ações, sem apagar um comando. Restaurar controles padrão desfaz remapeamentos e a escolha manual de símbolos.
- Controle: posição oeste (Xbox X / PlayStation quadrado) inspeciona; sul confirma e leste volta. Nomes ambíguos mostram posições genéricas, sem adivinhar hardware. A seleção manual de família altera símbolos, não identidade detectada.
- Permanecer no console por oito segundos elegíveis abre a história; não interrompe inspeção.
- Perder foco preserva a imagem e o estado, cancelando o arraste.

## Escopo atual

Master System e a amostra Adventure do Atari 2600. Entrar aproxima a câmera do console e revela uma biblioteca de caixas 3D, com frente, lombada e verso. O protótipo não emula jogos, mas as capas devem corresponder às embalagens originais disponíveis, sem reinterpretar a arte. O menu usa três cards reutilizáveis e até cinco caixas residentes, com escolha aleatória inicial estável e navegação explícita preservada. As mídias são carregadas de um manifesto local; não são distribuídas automaticamente por este repositório. Sem mídia configurada, a interface informa sua ausência em vez de inventar uma capa. Veja `docs/ARTES_LOCAIS.md`. Não há ROMs, execução de jogos, biblioteca pessoal conectada ou integração RetroAchievements. Nenhuma homologação Hardcore é alegada. Movimento reduzido troca de cena sem a animação de entrada; Voltar cancela a transição ou retorna ao console.

## Exposição do jogo selecionado

A seleção exibe dois controles reutilizados, cabos com comprimento nominal de 2 m organizados em voltas suaves, plugues moldados com alívio de tensão, caixa aberta ao fundo e um único cartucho do mesmo item do catálogo. Caixa e cartucho mantêm a escala nativa; ao voltar da biblioteca, o conjunto acompanha a seleção atual, sem misturar mídias. A caixa de fundo fica à esquerda, sem sobrepor o console, e mostra verso, lombada e frente em perspectiva própria; a câmera e os controles do console são preservados. A inspeção dedicada continua isolando o console. O carregador opcional de hardware local restaura os materiais e estampas REV2; sem esse recurso, a interface informa a ausência das texturas em vez de apresentar o controle neutro como equivalente. Veja [recursos locais](docs/HARDWARE_LOCAL.md) e [geometria da exposição](docs/EXPOSICAO_3D.md).

Na HOME do Master System, o encaixe continua uma apresentação estática com abertura visual reversível da carcaça. Na biblioteca, a sequência animada separada usa um override mecânico privado e mídia correspondente à entrada selecionada; veja [inserção SMS e seus limites](docs/SMS_INSERTION.md). Sem esses requisitos, a interface mantém o fallback explícito, sem animar arte de outro jogo. A articulação da caixa foi corrigida no runtime sem modificar sua geometria fechada ou o GLB original. Labels só aparecem quando fornecidos explicitamente para aquele item. O manual original de Wonder Boy foi validado em configuração privada com suas 32 páginas; as digitalizações não fazem parte deste repositório. Wheel original não foi fornecida nessa configuração: quando houver uma imagem vinculada à entrada ela substitui o título, e quando não houver o texto legível permanece. O leitor integrado recebe o mesmo livreto sob as presilhas, apresenta folhas 3D e oferece leitura ampliada das páginas PNG/JPEG locais vinculadas ao jogo, sem substituir páginas ausentes; conversão de PDF no aplicativo e obtenção online permanecem pendentes. Veja [manual local](docs/MANUAL_LOCAL.md). A ação Abrir mantém a apresentação/inspeção da caixa e do cartucho, sem execução. A ação Inserir usa o fluxo mecânico condicional descrito acima.

## Catálogo e variantes

A coleção usa três cards e até cinco caixas residentes. O sorteio considera entradas elegíveis, mantém a escolha durante foco/layout/inspeção e evita repetição imediata quando uma nova visita explícita tem alternativas. Variantes continuam distintas pelo sistema e caminho relativo, mesmo compartilhando um ID externo.

`cosmic/catalog_import.gd` adapta um JSON de inventário fornecido explicitamente, sem ler ROMs, diretórios ou mídias. Master System e Mark III são grupos separados. Entradas ausentes ficam consultáveis, mas não entram no sorteio. Sem raiz local configurada, as referências de mídia não são tratadas como imagens presentes nesta máquina.

A UI identifica esse modo como inventário de origem, sem alegar presença local. Os cards mostram indícios do nome do arquivo (região, idioma e revisão quando fornecidos), não uma edição confirmada. Basename e ordinal distinguem rótulos coincidentes sem expor diretórios privados. Cache e virtualização são limitados; testes com mil registros sintéticos não representam artes reais carregadas.

## Testes

Execute no diretório do projeto, por exemplo:

    godot --headless --path . --script cosmic/test_selection.gd
    godot --headless --path . --script cosmic/test_history.gd
    godot --headless --path . --script cosmic/test_inspection.gd
    godot --headless --path . --script cosmic/test_focus_visibility.gd
    godot --headless --path . --script cosmic/test_controls.gd
    godot --headless --path . --script cosmic/test_controls_propagation.gd
    godot --headless --path . --script cosmic/test_library.gd
    godot --headless --path . --script cosmic/test_library_view.gd
    godot --headless --path . --script cosmic/test_library_propagation.gd
    godot --headless --path . --script cosmic/test_library_catalog.gd
    godot --headless --path . --script cosmic/test_collection_scan.gd
    godot --headless --path . --script cosmic/test_game_media.gd
    godot --headless --path . --script cosmic/test_exhibit.gd
    godot --headless --path . --script cosmic/test_exhibit_integration.gd
    godot --headless --path . --script cosmic/test_zoom_stress.gd

Em Linux/macOS, `bash tools/verify_project.sh` executa a importação, a suíte e a auditoria de imagens antigas em sequência.

Relatórios gerados ficam em `evidence/cosmic/`, fora do versionamento. Testes headless não substituem QA visual, teste Windows ou validação na GPU do usuário.

## Recursos e limites

Veja `LEIA-ME_SISTEMAS_NO_INFINITO.md` e os documentos de procedência junto aos assets. Fontes incluem licenças OFL. Nomes e marcas pertencem aos seus titulares; não há licença comercial presumida para marcas. As inscrições foram reconstruídas em SVG e rasterizadas em 4K, sem a fotografia de loja usada no protótipo anterior. O runtime limita o atlas a 2K sem perdas, com mipmaps e filtro anisotrópico; os fontes 4K permanecem editáveis. A tipografia do wordmark é uma aproximação documentada, não a fonte industrial original.

Não incluir jogos, saves, credenciais, caches, builds ou mídias pessoais neste repositório público.

## Próximos incrementos de configuração

O guia opcional de mídia local já está disponível pela ação Mídia local: sistema, raiz e categorias explícitas, com Pular e Configurar depois. Ele conta arquivos separadamente de jogos e associa somente referências locais validadas, conforme os limites do checkpoint abaixo. Permanecem pendentes o tour automático no primeiro uso, a fila completa de conversão/preparação e a obtenção online. Nenhum fluxo baixa ROMs.

Revisão do controle 3D: corrigido fechamento inesperado após clicar Voltar durante Testar entradas e salvar depois. Cobertura adicional de layout P1/P2/conflitos em 16:9 e 4:3; o visual/modelo aprovado permanece inalterado. Windows e gamepads físicos continuam pendentes.

## Atari 2600 — checkpoint integrado (2026-10-25)

O seletor inclui Atari como segundo sistema. A biblioteca contextual permite inspecionar caixa, cartucho único e manual 3D com quatro folhas/oito faces, quando fornecidos pelo manifesto privado explícito `RETROPASS_ATARI_MEDIA_MANIFEST`. Sem manifesto, não cria modelos substitutos nem promete mídia disponível. Os modelos não são distribuídos neste repositório.

O fluxo inclui Voltar, foco de teclado/D-pad e perfil de navegação do frontend; não altera o remapeamento de gameplay do Master System. O carregamento dos cinco modelos é adiado até abrir a biblioteca. Mantém a perspectiva Master System aprovada.

No checkpoint inicial descrito acima, as abas originais abriam/fechavam e havia inspeção; a sequência contínua de retirada/encaixe foi adicionada na integração descrita abaixo. Não executa jogos nem emulação. Correspondência exata da edição e licença de redistribuição seguem sem confirmação. QA visual realizado no Godot cloud Linux em 1024×768 e 1152×648; não equivale a teste Windows, GPU do usuário ou gamepad físico.

Verificação do checkpoint: importação Godot e `tools/verify_project.sh` concluídas (53 scripts, persistência em dois processos e auditorias); testes privados de cinco GLBs, biblioteca e alternância SMS↔Atari também passaram. Regressões incluem ausência de mídia, foco/Back remapeado, D-pad contextual, cancelamento e histórico automático. Evidências e complemento privado ficam fora do Git.

## Atari — inserção reversível

A coleção Atari possui o fluxo reversível `Inserir cartucho`, usando o mesmo cartucho nativo e as quatro articulações originais da caixa. Voltar devolve o cartucho à caixa antes de permitir a saída; a perda de foco pausa o movimento e a preferência de movimento reduzido é respeitada. Não há emulação. Os controles de inspeção e manual permanecem disponíveis fora da animação. Mídia ausente ou alterada desabilita a inserção sem criar arte substituta. Consulte `docs/ATARI_INSERTION_INTEGRATION.md` para os limites geométricos, a câmera preservada e os critérios de verificação.

## Entrada automática Atari

Ao confirmar o console, a escolha usa o catálogo disponível daquele sistema. Para Atari, Adventure é a única entrada explicitamente fornecida. A inserção do mesmo cartucho começa uma única vez depois que a transição de entrada termina, sem nova confirmação. Voltar à caixa não reinicia a sequência. Perder foco antes do início cancela a intenção automática e mantém o botão manual; durante o movimento, apenas pausa. O Master System conserva sua seleção existente e só inicia sua sequência quando o override mecânico privado e a mídia vinculada à mesma entrada/variante passam pelos respectivos gates; caso contrário, informa a indisponibilidade sem resorteio. Isso não significa que todas as entradas do inventário tenham mídia ou animação disponível. Consulte [entrada Atari](docs/AUTOMATIC_ENTRY.md) e [inserção SMS condicional](docs/SMS_INSERTION.md) para os contratos e limites.

## Inserção SMS com override mecânico privado

A biblioteca pode abrir a caixa com dois eixos, extrair seu próprio cartucho e inseri-lo no console em um único mundo transitório, com Voltar reversível e restauração da câmera. A HOME não é alterada. O sorteio conserva elegibilidade, ID e variante; sem mídia correspondente ou geometria validada, permanece o fallback explícito, sem trocar jogo nem executar ROMs. A amostra legada requer vínculo privado por hash, sem inferir revisão/região.

Veja [contrato e limites](docs/SMS_INSERTION.md). Geometria derivada, bindings de mídia, caches e evidências permanecem privados.

## Mídia local opcional — integração de sessão

O botão **Mídia local** no HOME abre um guia opcional. Nada é selecionado por
padrão: escolha sistema, raiz absoluta e categorias; **Pular** e **Configurar
depois** preservam a navegação. A revisão mostra sistema/raiz/categorias do plano
real. Só **Confirmar processamento local** com a escolha OK focada autoriza o
worker. Cancelar, inclusive com controles remapeados, nunca autoriza leitura.

- O guia usa somente `media_metadata` de entradas já carregadas pelo catálogo;
  não inicia scanner, não lê ROMs, não procura jogos por nome e não busca rede.
  O scanner de pastas, cache de arte e wheel existentes permanecem disponíveis.
- Um painel/serviço é dono do journal privado `user://`. Fechar o guia não mata
  o worker; progresso de arquivos fica no botão/tooltip e detalhes no painel.
  Cancelar é cooperativo; sair do aplicativo cancela e faz join seguro.
- Configuração e último plano são persistidos privadamente com limite16MiB,
  validação e backup. Reiniciar **oferece** retomada, nunca a executa. A retomada
  exige confirmação nova e relê todos os arquivos, inclusive já concluídos.
- Leitura/hash e associação são fases distintas. Após leitura, o mesmo worker
  revalida hash e decodifica bytes atuais PNG/JPEG/WebP suportados, com limites
  de 64 MiB de arquivo e 64 Mi pixels reutilizados do cache. Nenhuma textura/GPU é
  criada nesse worker. Hash sozinho não valida imagem, jogo ou edição.
- Só referências exatas de ID+sistema+variante+tag/superfície são associadas;
  mudança de inventário entre consentimento e aplicação descarta o resultado.
  Aliases conflitantes, ausências e formatos inválidos permanecem explícitos.
  Capas/labels e wheel não são inferidos de screenshots ou imagens genéricas.
- Associações atualizam uma **cópia do catálogo em memória nesta sessão**,
  preservando a superfície anterior/procedência. Arquivo do catálogo original
  e mídias originais não são sobrescritos. Cache é invalidado inclusive quando
  bytes mudam no mesmo caminho; caixa/wheel atualizam na próxima entrada normal
  da biblioteca, sem sortear outro jogo. Não se reaplica resultado salvo no boot.
- Contagens separam arquivos lidos, jogos com leitura completa, erros de arquivo,
  omissões e vínculos aplicados/não aplicados. Não há download, importação de
  ROM, emulação, conversão PDF, geração de páginas, thumbnails ou compressão.

**Limites:** este incremento não é uma fila completa de preparação multimídia.
O cache existente ainda faz preload/resize/texturas na navegação. PDF/manual e
imagens genéricas podem ser lidos/hashados se selecionados, mas não são aplicados
como capas/páginas. O inventário Atari atual não fornece o contrato de
`media_metadata`; o guia informa ausência de referências, sem alegar aplicação
Atari. Mark III também depende de entradas com sistema exato. Fontes locais devem
permanecer estáveis: substituição maliciosa após validação (TOCTOU) não é eliminada.
Shutdown pode aguardar I/O/decode em andamento. Um dono por journal dentro do app;
não há lock para múltiplos processos. Caminhos/journals/hashs são privados, nunca
parte da publicação.

Testes sintéticos: `tools/verify_project.sh` inclui configuração/plano/fila,
persistência em 3 processos, serviço/painel, store, associação e consentimento
remapeado (inclusive Cancel com Enter/Espaço/gamepad). QA é cloud Linux; não
comprova controle físico, diálogo Windows ou GPU do usuário.

Verificação deste incremento (cloud Linux): o componente 2D real foi exercitado
em 1152×648 e 1024×768, com confirmação, cancelamento, leitura e retomada.
Uma execução do main 3D em 16:9 abriu o guia e voltou pela opção Pular; o fluxo
completo de processamento e o main 4:3 não foram validados visualmente juntos.
As tentativas de import CLI terminaram externamente (-9/137), sem diagnóstico
causal fechado. A suíte incremental é executada separadamente usando cache de
assets idêntico à base; isso não equivale a import limpo nem ao PASS integral do
script incluindo sua etapa de importação. A comparação visual base/candidato
teve mudança espontânea de processo do navegador, portanto não prova causalidade.

Próximo passo: import limpo em ambiente estável e QA integrado completo em 4:3/16:9,
seguido de Windows/controle físico. A fila completa de conversão e download não
faz parte deste checkpoint.
