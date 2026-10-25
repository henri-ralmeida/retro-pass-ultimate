# RETRO PASS ULTIMATE
## Sistemas no Infinito · protótipo Master System

Projeto-fonte Godot, não um executável Windows exportado. Contém somente o Master System e uma biblioteca conceitual de caixas 3D fictícias, sem ROM, emulação ou biblioteca pessoal conectada.

### Abrir
1. Clone o repositório ou atualize a branch `feature/master-system`, sem sobrepor arquivos locais não versionados.
2. Importe `project.godot` no Godot **4.6.3** e pressione F5.
3. O renderizador é **Compatibility**; a cena inicial é `cosmic/main.tscn`.
O Blender não precisa estar instalado para executar, pois a apresentação carrega o GLB.

### Controles escolhidos
Rodapé contextual do estudo **09 (ES-DE)**: indicador circular de tecla e rótulo, sem grandes superfícies ou ícones flutuantes.
- Clique no console, ou Enter/Espaço quando em foco: emitir seleção.
- Clique em **I Inspecionar**, ou pressione I: abrir a manipulação 3D. Arraste para girar, use roda/+− para zoom e R para restaurar. I ou Esc fecha.
- Page Up/Down ou roda do mouse: rolar o texto histórico. Toda abertura retorna ao início do texto.
- Clique em **M Reduzir movimento**, ou pressione M: congelar movimento. O rótulo muda para Retomar movimento.
- Tab: alternar foco entre os controles disponíveis. A inspeção acrescenta Restaurar. Enter/Espaço ativa o controle em foco.
- Hover/foco realça o controle em azul. Alvos de mouse de 240×48, tooltips e nomes de acessibilidade explícitos.
- Esquerda/direita: navegação circular preparada por dados; com um único sistema, não simula troca.
- Mapeamento de gamepad A/D-pad preparado, sem afirmar conexão nem teste físico de controle.

Apenas o logotipo do Master System aparece abaixo do console, sem repetir seu nome em texto. O nome interno e acessível permanece preservado. A marca do aplicativo é **RETRO PASS ULTIMATE**, com espaços, sem barra.

Hover não seleciona, inicia mídia ou emulação. A confirmação aproxima a câmera e entra na biblioteca conceitual 3D. Não abre o quarto nem executa jogos.

### Integração e dados
`cosmic/system_data.gd` declara identificador, nome, subtítulo, modelo, transformação, câmera/enquadramento, `logo: Texture2D`, `logo_source`, `history_text`, `history_credits` e `history_sources`. `cosmic/master_system.tres` é o único registro real.
Contrato: sinal `system_selected(system_id: String)`, payload `sega_master_system`. A rota visual da biblioteca consome a seleção; as capas são estudos fictícios, não edições comerciais. Cooldown de 400 ms, rejeição de repetição automática de tecla e proteção no retorno de foco evitam ações duplicadas/carregadas.
Nome textual só serve como fallback visual quando um sistema não possui logo. A navegação, câmera e logo são orientados por dados, sem condições específicas por console no controlador.

### Visual e movimento
Fundo procedural próprio azul/violeta, três campos estelares com velocidades distintas, nebulosa em movimento e cometas ocasionais. Não copia recursos do Cartridge. Sem piso, sala, pedestal ou universo geométrico enorme.
Aparelho flutua suavemente em 3 mm, sem rotação contínua; luz realça hover/foco. M interrompe movimento/parallax/cometas. Janela sem foco pausa a animação e cancela arraste/espera, mas mantém a imagem 3D visível e preserva ângulo/zoom. Apenas uma cena explicitamente desativada interrompe o viewport.
Ajustes no shader: `motion_speed`, `star_density`, `nebula_brightness`, `comets_enabled`. Duas luzes direcionais sem sombras e luz ambiente. MSAA 4×. Limite configurado de 60 FPS não é medição nem promessa de desempenho.

### Modelo e procedência
- `assets/cosmic_console/MasterSystem_Console.glb`: console com imagens embutidas.
- `assets/cosmic_console/source_blender/MasterSystem_Console_EDITABLE.blend`: editável com texturas empacotadas, Blender 4.3.2.
- `MODEL_AUDIT.json` nessa pasta: geometria e rastreabilidade.
O editável atual contém a geometria do protótipo, as inscrições vetoriais próprias e a correção do rebaixo Sega Card. A correção acrescenta piso e guia internos sem copiar a fotografia física de referência; preserva os buffers anteriores, texturas e limites externos. O GLB atual tem 184 meshes e 29.458 triângulos. Consulte `MODEL_AUDIT.json` e `CARD_RECESS_REPAIR_AUDIT.json` para os hashes e detalhes. Backups anteriores permanecem fora do repositório.

Logotipo: PNG original 1000×300, sem redesenhar, recolorir ou substituir por fonte; atribuído à Sega no [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Sega-master-system-logo.png). `assets/system_logos/PROVENIENCIA.txt` registra hash, fonte e ressalva de trademark. A classificação PD-textlogo da fonte não constitui autorização comercial da Sega. O SVG popular fan-made com fonte incorreta foi evitado.
Fontes Orbitron e Chakra Petch obtidas do repositório oficial Google Fonts, com licenças OFL locais. A geometria e o ícone do aplicativo foram construídos durante o projeto; a procedência e os elementos de marca estão documentados junto aos assets. Ícones anteriores preservados nos assets, sem uso na UI atual.

### Testes e evidências
`godot --headless --path CAMINHO --script cosmic/test_selection.gd`
Os relatórios gráficos completos acompanham as entregas ZIP. Neste checkout, os testes regeneram JSON/logs locais em `evidence/cosmic/`. Testes headless não substituem as capturas gráficas reais em 16:9 e 4:3. Render Blender é identificado separadamente e não comprova funcionamento da UI.

Capturas de estados: `godot --path CAMINHO -- --capture-cosmic`.
Prévia offline: `godot --path CAMINHO --audio-driver Dummy --fixed-fps 30 -- --capture-offline`.
São 360 PNGs reais do viewport, após aquecimento, em `evidence/cosmic/offline_frames/`. Codifique a 30 FPS: representam 12 s de simulação, sem quadros interpolados. Podem levar mais tempo para renderizar. PNGs temporais brutos não acompanham o ZIP; o MP4 final acompanha.

A prévia OFFLINE não demonstra 30 FPS em tempo real. A medição separada `--runtime-metrics`, realizada antes da inclusão do logo e do rodapé final, obteve 23,64 FPS médios no llvmpipe de nuvem, sem captura. Não foi repetida nesta revisão nem representa hardware do usuário.

### Limites e preservação
O pontilhado especular severo foi corrigido; podem restar pequenos serrilhados subpixel em costuras. Windows, EXE exportado, GPU do usuário e controle físico não foram testados.
O projeto anterior foi preservado integralmente na origem. O checkout Git contém somente o protótipo cósmico; arquivos legados completos permanecem nas entregas ZIP anteriores, não foram apagados da origem. O desenvolvimento e a validação foram realizados na nuvem, sem instalação pessoal ou acesso ao desktop do usuário.

### História automática por permanência
Com o console em foco de teclado ou sob o ponteiro parado, após **8 segundos** abre a apresentação lateral com história, separada da inspeção 3D. O tempo é ajustável em `dwell_seconds`, na cena/script. Mouse e teclado têm elegibilidade separada: deixar o ponteiro fora do console não mantém o timer só porque restou foco de teclado. Ficar sobre os controles não dispara história.
Qualquer entrada relevante reinicia a espera; inatividade da cena/perda de foco aborta o contador. Abrir história não emite seleção, não inicia áudio, TTS, vídeo ou jogo. Fechar retorna ao centro e desarma abertura automática até nova entrada/foco/reentrada deliberada, evitando loop imediato. Movimento reduzido abre/fecha sem deslize.
O painel contém resumo autoral com base em páginas Sega/Tectoy e créditos. As URLs completas ficam nos dados do sistema e em `cosmic/HISTORIA_FONTES.md`. A descrição de um tema RetroBat foi localizada, mas não copiada: tinha licença própria e data brasileira divergente. Não existe integração ou leitura da instalação RetroBat.
Teste dedicado: `godot --headless --path CAMINHO --script cosmic/test_history.gd`. Relatórios em `history_tests.json` e `.log`, separados das regressões gerais. A captura offline reinicia o contador na primeira imagem para mostrar a espera e a abertura, sem acelerá-las.

## Revisão: inspeção 3D independente

O botão **Inspecionar** e a tecla **I** abrem agora um modo dedicado de manipulação do objeto, separado da história automática. Arraste sobre a área 3D para girar horizontal ou verticalmente, inclusive para ver a parte inferior. A roda do mouse ou +/− ajusta o zoom dentro de limites. As setas também giram; **R / Restaurar** repõe ângulo e zoom; **Esc / I / Voltar** sai. Nenhum desses comandos seleciona ou inicia um jogo.

O pivô é o centro da caixa geométrica do console. Durante inspeção a flutuação automática pausa. Movimento reduzido não impede a manipulação voluntária. Perder foco cancela o arraste. Botões e outros elementos fora da área 3D não iniciam rotação.

A história continua aparecendo após 8 segundos elegíveis sobre o console, fora da inspeção. Esc fecha a história; I troca da história para inspeção. O atraso é configurável em `dwell_seconds` de `cosmic/main.gd`.

### Correção do acabamento na renderização

O pontilhado branco severo foi isolado como aliasing especular em detalhes pequenos. A variante mantém geometria, normal maps e metais; aplica acabamento acetinado não destrutivo ao instanciar `MasterSystem_Console_Render.tscn`. Plásticos têm roughness mínimo 0,65 e specular máximo 0,25; metais mantêm metallic/specular e roughness mínimo 0,48. Filtro anisotrópico melhora inscrições. Os originais anteriores foram preservados fora deste checkout; o GLB e o Blend aqui usam as inscrições vetoriais reconstruídas.

A solução não depende de cache, alteração de compressão ou faixa especial de profundidade. Reimportação em uma cópia sem `.godot` passou, seguida de 358 verificações. Ainda existe serrilhado subpixel discreto em costuras em certos ângulos; não se promete ausência absoluta de aliasing.

### Inscrições, zoom e foco

As inscrições foram reconstruídas em SVG, com atlas e wordmark em alta resolução, sem pixels da fotografia de loja ou do logo fotográfico anterior. Os fontes 4K ficam em `assets/cosmic_console/source_art/raster/`; o atlas de runtime é limitado a 2K sem perdas pelo importador, preservando mipmaps e filtro anisotrópico. Preserve os arquivos `.import` para reproduzir essa configuração. O wordmark usa aproximação tipográfica documentada; a marca SEGA e o logo de sistema têm atribuições próprias. Veja `source_art/ATTRIBUTION.txt` e os manifests de auditoria.

O zoom permanece útil entre 0,65 e 1,35, com enquadramento adaptativo ao ângulo. A grade de testes inclui mais de cinco mil estados e três proporções. Não há promessa de nitidez infinita nem certificação em todas as GPUs. Perder foco preserva o objeto visível, orientação e zoom; arraste e contador são cancelados. A história pausada retoma da posição onde parou.


### Controles contextuais

A apresentação usa rodapé contextual sem subtítulo e instruções longas permanentes. Teclado: X confirma, Z volta, I inspeciona, M pausa/retoma, R restaura inspeção e F1 abre Controles. Setas e +/− continuam repetíveis durante inspeção; confirmação mantida não repete.

Ações e família de símbolos são configuráveis em `user://controls.cfg`. Xbox usa X para inspecionar; PlayStation usa quadrado, na mesma posição física oeste. Identidades ambíguas como XInput/Steam Input são genéricas até escolha manual. Os testes de gamepad são sintéticos, não validação com controle físico.
