# RETRO PASS ULTIMATE

Protótipo desktop em Godot 4.6.3, inicialmente para Windows. A direção atual é **Sistemas no Infinito**: um Master System 3D em fundo cósmico, com inspeção interativa e história do console. Substitui a proposta inicial de quarto 3D registrada no primeiro commit.

## Executar

1. Clone este repositório ou faça pull das atualizações.
2. Importe `project.godot` no Godot 4.6.3 e aguarde a importação dos recursos. Essa é a versão efetivamente testada; versões mais novas ainda precisam de validação.
3. Pressione F5. O renderizador é Compatibility.

Este repositório contém código-fonte, não um executável Windows já validado. Blender não é necessário para executar.

## Interações

- I / Inspecionar: manipulação 3D separada da história.
- Arraste para girar em dois eixos; roda ou +/− para zoom; setas também giram.
- R / Restaurar: orientação e zoom iniciais. Esc / I / Voltar: sair.
- M: reduzir movimento.
- Permanecer no console por oito segundos elegíveis abre a história; não interrompe inspeção.
- Perder foco preserva a imagem e o estado, cancelando o arraste.

## Escopo atual

Somente Master System. Sem ROMs, emulação, biblioteca conectada ou integração RetroAchievements. A seleção emite um sinal preparado para integração futura. Nenhuma homologação Hardcore é alegada.

## Testes

Execute no diretório do projeto, por exemplo:

    godot --headless --path . --script cosmic/test_selection.gd
    godot --headless --path . --script cosmic/test_history.gd
    godot --headless --path . --script cosmic/test_inspection.gd
    godot --headless --path . --script cosmic/test_focus_visibility.gd
    godot --headless --path . --script cosmic/test_zoom_stress.gd

Em Linux/macOS, `bash tools/verify_project.sh` executa a importação, a suíte e a auditoria de imagens antigas em sequência.

Relatórios gerados ficam em `evidence/cosmic/`, fora do versionamento. Testes headless não substituem QA visual, teste Windows ou validação na GPU do usuário.

## Recursos e limites

Veja `LEIA-ME_SISTEMAS_NO_INFINITO.md` e os documentos de procedência junto aos assets. Fontes incluem licenças OFL. Nomes e marcas pertencem aos seus titulares; não há licença comercial presumida para marcas. As inscrições foram reconstruídas em SVG e rasterizadas em 4K, sem a fotografia de loja usada no protótipo anterior. O runtime limita o atlas a 2K sem perdas, com mipmaps e filtro anisotrópico; os fontes 4K permanecem editáveis. A tipografia do wordmark é uma aproximação documentada, não a fonte industrial original.

Não incluir jogos, saves, credenciais, caches, builds ou mídias pessoais neste repositório público.
