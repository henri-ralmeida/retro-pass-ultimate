# RETRO PASS ULTIMATE

Protótipo desktop em Godot 4.6.3, inicialmente para Windows. A direção atual é **Sistemas no Infinito**: um Master System 3D em fundo cósmico, com inspeção interativa, história do console e entrada animada em uma biblioteca de caixas 3D. Substitui a proposta inicial de quarto 3D registrada no primeiro commit.

## Executar

1. Clone este repositório ou faça pull das atualizações.
2. Importe `project.godot` no Godot 4.6.3 e aguarde a importação dos recursos. Essa é a versão efetivamente testada; versões mais novas ainda precisam de validação.
3. Pressione F5. O renderizador é Compatibility.

Este repositório contém código-fonte, não um executável Windows já validado. Blender não é necessário para executar.

## Interações

- X entra no sistema e Z volta no teclado. Enter/Espaço continuam como alternativas de confirmação.
- I / Inspecionar: manipulação 3D separada da história.
- Arraste para girar em dois eixos; roda ou +/− para zoom; setas também giram.
- R / Restaurar: orientação e zoom iniciais. Esc / Z / I / Voltar: sair.
- M: pausar/retomar movimento.
- Escanear jogos, na biblioteca: escolher uma pasta para catálogo local. Não executa arquivos, não altera a coleção e não faz consultas online sem integração configurada. Capas locais explicitamente associadas preenchem cada face disponível.
- F1 / Controles, na tela do console: escolher família de símbolos e remapear teclas/botões; configuração persiste localmente. Conflitos trocam as duas ações, sem apagar um comando. Restaurar controles padrão desfaz remapeamentos e a escolha manual de símbolos.
- Controle: posição oeste (Xbox X / PlayStation quadrado) inspeciona; sul confirma e leste volta. Nomes ambíguos mostram posições genéricas, sem adivinhar hardware. A seleção manual de família altera símbolos, não identidade detectada.
- Permanecer no console por oito segundos elegíveis abre a história; não interrompe inspeção.
- Perder foco preserva a imagem e o estado, cancelando o arraste.

## Escopo atual

Somente Master System. Entrar aproxima a câmera do console e revela uma biblioteca de caixas 3D, com frente, lombada e verso. O protótipo não emula jogos, mas as capas devem corresponder às embalagens originais disponíveis, sem reinterpretar a arte. As mídias são carregadas de um manifesto local; não são distribuídas automaticamente por este repositório. Sem mídia configurada, a interface informa sua ausência em vez de inventar uma capa. Veja `docs/ARTES_LOCAIS.md`. Não há ROMs, execução de jogos, biblioteca pessoal conectada ou integração RetroAchievements. Nenhuma homologação Hardcore é alegada. Movimento reduzido troca de cena sem a animação de entrada; Voltar cancela a transição ou retorna ao console.

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
    godot --headless --path . --script cosmic/test_zoom_stress.gd

Em Linux/macOS, `bash tools/verify_project.sh` executa a importação, a suíte e a auditoria de imagens antigas em sequência.

Relatórios gerados ficam em `evidence/cosmic/`, fora do versionamento. Testes headless não substituem QA visual, teste Windows ou validação na GPU do usuário.

## Recursos e limites

Veja `LEIA-ME_SISTEMAS_NO_INFINITO.md` e os documentos de procedência junto aos assets. Fontes incluem licenças OFL. Nomes e marcas pertencem aos seus titulares; não há licença comercial presumida para marcas. As inscrições foram reconstruídas em SVG e rasterizadas em 4K, sem a fotografia de loja usada no protótipo anterior. O runtime limita o atlas a 2K sem perdas, com mipmaps e filtro anisotrópico; os fontes 4K permanecem editáveis. A tipografia do wordmark é uma aproximação documentada, não a fonte industrial original.

Não incluir jogos, saves, credenciais, caches, builds ou mídias pessoais neste repositório público.
