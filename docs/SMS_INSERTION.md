# Inserção SMS no mundo da biblioteca

A sequência usa o cartucho canônico da caixa selecionada, sem mudar seu pai: enquadramento transitório, abertura dos dois eixos existentes, extração, folga para rotação, transferência e contato cinemático com a porta do console. Voltar percorre o mesmo relógio no sentido inverso. HOME e sua combinação de câmeras não são alteradas.

A câmera perspectiva da biblioteca mantém projeção, FOV e orientação. O enquadramento considera o menor aspecto 2:1 do viewport 3D: no layout de janela 1152×648 ele mede 1024×324; em 1024×768 mede 896×444. Não se confunde o aspecto da janela com o viewport. Esse limite conservador evita recalcular/saltar o objetivo da câmera ao alternar os dois formatos durante a animação. Posição/enquadramento mudam continuamente e são restaurados ao retornar. Console, caixa e cartucho compartilham a transformação nativa capturada, incluindo a escala de apresentação da caixa; a escala não é aplicada duas vezes. O console entra a partir de fora do enquadramento, não por uma troca de câmera. Movimento reduzido aplica estados completos; foco perdido pausa uma sequência iniciada, mas invalida intenção automática ainda pendente.

## Seleção e mídia

`CatalogChoice` continua responsável pela elegibilidade do inventário e pelo sorteio na visita deliberada ao console/catálogo. O token de autostart é outro ciclo: renova a cada entrada na biblioteca, mas não resorteia. Voltar à HOME e reabrir o mesmo console preserva a seleção exibida; nova ativação de console ou scan explícito inicia a visita deliberada de catálogo. Presença no inventário de origem não comprova bytes de ROM ou mídia local na nuvem. A inserção só começa depois de verificar a mídia vinculada à entrada e os contratos geométricos. Ausência não causa novo sorteio, troca de variante ou uso de arte de outro jogo. Não há execução, emulação, leitura ou download de ROMs.

A amostra legada Wonder Boy possui a mesma foto original para label e topo com UVs próprios. O vínculo é habilitado somente por contrato privado explícito, ID/variante exatos e hashes verificados. Isso não autentica região, revisão ou prensagem; a procedência da caixa mantém essa ressalva. Não é permitido liberar qualquer `art_root` por semelhança de nome.

## Override privado

- `RETROPASS_SMS_MECHANICAL_PATCH`: JSON privado de geometria derivada.
- `RETROPASS_SMS_MECHANICAL_PATCH_SHA256`: hash esperado fornecido explicitamente.
- `RETROPASS_SMS_MEDIA_BINDING`: vínculo privado da amostra legada quando não há campos explícitos de label/topo.

GLBs, JSON de triângulos, texturas, bindings locais, caches e evidências não pertencem ao pacote público. O loader valida hashes da cena e suas dependências, cria novas meshes apenas no candidato e mantém recursos compartilhados de origem imutáveis. Conversão de winding glTF/Godot e geração de tangentes preservam normals/UVs de origem. Não há recorte por shader nem remoção da porta/dobradiças.

## Limites

A trajetória e a cavidade são aproximações geométricas do modelo fornecido: folga técnica de 0,2 mm, eixo inferido, interior não medido de hardware. Não simulam força, mola, atrito, conector elétrico ou fabricação. Varreduras amostradas não são prova contínua. A sessão usa a dupla dobradiça; o fluxo anterior de inspeção manual da biblioteca ainda usa sua apresentação de eixo único, de maneira mutuamente exclusiva.

A validação deve incluir trajetória completa com manual/presilhas, reversão em fases intermediárias, identidade/pai únicos, foco, retorno exato da câmera, falhas com nós removidos, visitas repetidas e provas visuais em 16:9 e 4:3. Testes cloud Linux não comprovam Windows ou controle físico.

## Regressão de caminho intermediário da capa

Os ângulos finais são os mesmos da caixa perspectiva aprovada: base–lombada 90° e lombada–tampa 10,345512025270239°, ambos interpolados a partir da pose fechada. A alternativa 90°/90° foi descartada: em processamento natural, um ângulo intermediário ultrapassava a região validada do helper da margem da capa, embora poses pontuais passassem. O guard permanece ativo; o teste natural integrado verifica o caminho completo e impede a reintrodução dos ângulos incompatíveis. Falha continua exigindo saída segura, não avanço forçado ou desativação da verificação.

Os glifos repetidos de confirmação em **Abrir**, **Inserir** e **Manual** indicam ativação da ação em foco, não atalhos diretos concorrentes. `input_profile.confirm` (X por padrão) ativa somente o controle focado. O manual físico permanece no mesmo nó, sob as presilhas da tampa, durante a inserção; a leitura/retirada é uma ação separada depois do retorno.
