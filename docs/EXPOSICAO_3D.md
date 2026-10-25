# Exposição do Master System

## Geometria e medidas

A caixa e o cartucho usam o mesmo recurso articulado em todas as apresentações. A escala de exposição é nativa, em metros; o cartucho não aumenta ao sair da caixa. O modelo original permanece intacto. A composição de fundo mostra a capa externa da caixa aberta, com verso à esquerda, lombada central e frente à direita, à esquerda do console e sem sobreposição projetada. A projeção da caixa é perspectiva, independente da câmera ortográfica aprovada do console; não se deforma a arte para imitar profundidade. A HOME mantém somente o cartucho inserido; não há cópia solta. O cartucho da biblioteca continua disponível para inspeção e apresentação. Não há manual substituto ou arte inventada no interior.

A articulação antiga da caixa estava no fundo, abaixo da junção física. Na montagem de runtime, o eixo passa pela aresta superior externa da parede da lombada, derivada dos vértices existentes. Os filhos da tampa recebem a compensação inversa: fechada, toda a geometria e a arte mantêm a posição original. O giro é limitado a 0–115°. Isso corrige o afastamento herdado sem redesenhar a caixa. Não se trata de uma medida industrial do fabricante.

O cartucho exposto deixa aproximadamente 26 mm acima da borda, estimados pela referência fotográfica de um Power Base com cartucho do mesmo formato. A carcaça original tem superfícies sólidas sob o slot. Por isso a exposição usa um recorte visual limitado aos dois revestimentos nessa região e reposiciona o piso existente. Ao inspecionar o console isolado, os materiais, o piso e a tampa de proteção retornam exatamente ao estado original. Ainda não é uma simulação mecânica de inserção.

Os plugues moldados são geometria autoral aproximada a partir de fotografias de hardware. Preenchem o rebaixo medido no modelo e incluem alívio de tensão. Não há alteração das portas do console nem alegação de CAD original.

## Cabos

O manual de serviço SEGA identifica o conjunto C-12 / 600-5306 do Control Pad 3020 como “Assy Cable 9P L = 2m 3020”, na página impressa 23 (página 24 do PDF):
https://www.smspower.org/uploads/Development/SegaMasterSystemServiceManual.pdf#page=24

A representação inicial usava fios muito mais curtos. Agora cada linha central tem aproximadamente 2 m, com tolerância de 2 mm no roteamento de exibição, distribuídos em voltas com entradas e saídas suaves. As terminações internas do conjunto não são especificadas no manual, portanto isso não é uma medida exata da capa externa do fio. Os testes verificam curvatura, separação entre voltas, distância entre os dois cabos e afastamento dos controles/plugues. A disposição enrolada é autoral, não um formato de fábrica. O diâmetro de 3 mm usado no protótipo é uma estimativa visual, não uma especificação OEM confirmada.

## Validação e limites

Os testes verificam a preservação da caixa fechada, contato da articulação nos ângulos intermediários, restauração de recursos, encaixe, enquadramento por malha e continuidade da câmera. Testes geométricos não substituem a comparação visual em execução real. As texturas originais locais e sua instalação são descritas em HARDWARE_LOCAL.md; elas não estão incluídas automaticamente no repositório público.

## Perspectiva e articulação da caixa de fundo

A referência visual tem alturas aparentes diferentes conforme a profundidade. Uma câmera ortográfica não reproduz essa convergência alterando somente a abertura da tampa. A caixa de fundo usa um mundo 3D transparente separado e o mesmo catálogo/asset da biblioteca. A câmera, as dimensões, os UVs e os ângulos dessa prova não mudam com a proporção da janela: somente escala e translação do frustum ajustam o quadro. A caixa original no mundo do console é um envelope de posicionamento não renderizado, mantendo o enquadramento dos controles/cabos estável. Não há uma segunda caixa visível ou outro cartucho solto.

Fotos físicas de caixas identificadas pelos vendedores como originais mostram duas linhas de flexão em torno de uma lombada de largura finita:
- https://retrogamefan.com/products/double-dragon-sega-master-system-good
- https://www.ebay.com/itm/296015012225

Essas imagens fundamentam a articulação em três segmentos, não um ângulo de fábrica. A pose visual usa deltas independentes de 90° e aproximadamente 10,346° desde fechado, com projeção calibrada por cantos da referência. A geometria rígida é uma aproximação da flexão real do plástico, não CAD industrial.

A correção superior já aprovada é preservada. A nova articulação inferior deriva da borda existente da parede. Uma margem livre de 2 mm da folha da lombada dobra até 3,507° para não entrar na tampa, preservando comprimento, UVs e o recurso fechado exato. Não se corta nem estica a capa. Folhas separadas, bordas plásticas salientes e algumas sobreposições herdadas do modelo continuam documentadas; não se promete manga contínua ou ausência universal de colisões em ângulos arbitrários.

A prova isolada verificou 181 poses de abertura e retorno, contatos e triângulos reais. A regressão integrada cobre foco, inspeção, história, entrada interrompida, reconstrução pelo jogo selecionado e proporções 16:9/4:3. A camada não recebe input e desaparece durante inspeção do console, história e biblioteca. A aprovação estética da composição é distinta desses testes.
