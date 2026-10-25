# Modelos fictícios de caixa

Estas artes foram desenhadas originalmente para o protótipo visual RETRO PASS ULTIMATE. Os arquivos não contêm ROMs, fotografias, capturas de jogos, capas comerciais, logotipos de editoras, personagens reproduzidos nem materiais extraídos de jogos.

Alex Kidd e Wonder Boy são apenas referências nominais da interface. Não há afirmação de edição, plataforma específica, ano, licença, afiliação, parceria ou endosso dos titulares. As paisagens geométricas, a composição, os elementos de aventura e a identidade RETRO PASS ULTIMATE são estudos visuais originais. As artes de frente, lombada e verso identificam o material como fictício e não oficial.

## Arquivos e reprodução

- `alex_kidd_front.svg`, `alex_kidd_back.svg`, `alex_kidd_spine.svg`, `alex_kidd_edge.svg`: primeiro estudo, escolhido após a correção do usuário para Alex Kidd.
- `wonder_boy_front.svg`, `wonder_boy_back.svg`, `wonder_boy_spine.svg`, `wonder_boy_edge.svg`: segundo estudo coerente para demonstrar a mudança de item.
- `generate_covers.py`: fonte editável da composição, formas, cores e textos. Execute com Python e fontTools a partir de qualquer diretório para regenerar os oito SVGs.
- Os SVGs preservam vetores editáveis. Toda a tipografia é convertida em curvas para importação consistente no Godot, sem depender de suporte ao elemento SVG `text`.
- As fontes usadas são Orbitron e Chakra Petch, já presentes em `assets/fonts/`, sob as licenças OFL que acompanham o projeto. Não foi usada a tipografia dos logotipos comerciais dos jogos.

## Geometria

`cosmic/game_box.gd` constrói uma caixa real em 3D, com corpo plástico chanfrado/arredondado, frente, verso, lombada, bordas superior e inferior, linha de abertura e frisos moldados. Dimensão nominal: 1,74 × 2,44 × 0,30 unidades. Centro na origem; frente +Z, verso −Z, lombada −X. A geometria não pretende reproduzir as medidas de uma embalagem comercial específica.

O módulo é exclusivamente de apresentação. Não carrega ROMs, não executa jogos e não acessa contas ou bibliotecas reais.
