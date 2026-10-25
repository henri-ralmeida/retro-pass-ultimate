# Frontend integrado, ícones e leitura de conquistas

## Estado implementado

O botão de troféu abre um painel integrado à biblioteca, sem retirar a câmera ou o modelo 3D da coleção. A mesma superfície é usada no Master System e no Atari. Os controles de ação são ícones vetoriais locais com tooltip de mouse e foco e nome/descrição acessíveis; os títulos, descrições, vínculos de entrada, avisos e demais dados continuam sendo texto.

Abas: troféus, comentários do jogo e hubs. Confirmar uma conquista abre seus comentários; voltar recupera a linha original. Hubs têm lista de jogos relacionados e filtro de console; o catálogo retornado é explicitamente parcial. Ordenação e filtros têm ícones, foco circular e Voltar hierárquico. Conteúdo longo é rolável. Filtros: todas, desbloqueadas, bloqueadas, Beaten Path e missable. Ordem RA, A–Z, Z–A, pontos maiores/menores, raridade menor/maior e desbloqueadas/bloqueadas primeiro.

Não existe provedor RA nem identificação pessoal configurada neste checkout. A UI mostra essa ausência. Não busca dados automaticamente, não interpreta título/arquivo de ROM como ID confirmado, não pede nem guarda credenciais, não publica comentários e não fabrica progresso. Fixtures existem somente nos testes explicitamente identificados.

## Contrato para futuro adaptador autorizado

`open_for(item, return_focus, adapter)` exige `item.ra_game_id` confirmado e um objeto com `request_read(consumer, ticket)`. O adapter chama `consumer.accept_response(ticket, result)` com o ticket **inteiro e inalterado**. A UI não implementa transporte HTTP nem armazena chaves.

Ticket: `generation`, `serial`, `game_id`, `view`, `target_id`, `page`. Views: `achievements`, `game_comments`, `achievement_comments`, `hubs`, `hub_members`. Respostas de outro jogo/view/alvo/página/geração e respostas após fechar são descartadas. Falhas são `{ok:false,error:"..."}`; sucesso `{ok:true,records:[...],has_more:false}`. O adapter deve aplicar seus próprios limites de rede, schema e autorização. Máximo de 5000 registros por resposta; respostas maiores são erro, nunca truncamento silencioso.

Conquista normalizada: `id`, `title`, `description`, `points`, `display_order`, `type` (`progression`, `win_condition`, `missable`), `unlocked_hardcore`, `unlocked_softcore`; opcionais `rarity_hardcore`/`rarity_softcore` como porcentagem documentada e `badge_texture` já validada como Texture2D até 1024². Não passar caminhos/URLs de badge: a UI não os decodifica ou baixa. Adaptar o OLD explicitamente: `earnedHardcore` → hardcore, `earned` → softcore. `trueRatio/points` não é porcentagem oficial e não deve ser colocado nos campos de raridade percentual.

Comentários: `user`, `submitted`, `text`, exibidos literalmente em Label (sem HTML/BBCode). `has_more` deve vir da resposta válida; o número mostrado é apenas o já carregado. Falha de paginação mantém registros e índice, permitindo tentar a mesma página novamente. Hub: `id`, `name`, `loaded_count`; membros: `title`, `console`. IDs/quantidades podados do OLD não comprovam cobertura completa do hub.

Conjunto completo exige contagem exata e não vazia no modo selecionado; 199/200 nunca é completo. Softcore não desbloqueia Hardcore. “Beaten Path” agrupa tipos de progressão/condição de vitória: não é uma declaração oficial de jogo vencido. Pontos e contagens vêm da resposta atual, não de `max(cache,atual)`.

## Input e verificação

Um único dono de input: host → biblioteca → painel. A biblioteca suspende seus escritores de animação/arrasto enquanto o painel está aberto. Confirmar/Voltar usam o perfil atual, não posições de botão fixas. Direcional/Tab navegam ícones; ponteiro segue para o GUI apenas do modal. Gate de soltura na abertura/retorno, eventos held e perda/retorno de foco evitam ativação dupla. Fechar invalida a geração e restaura foco no lançador.

`cosmic/test_achievements.gd` cobre modelos, modos, filtros/ordens, erro/vazio/loading, paginação/retry, tickets stale, foco de conquista/hub, sort/Back, input held/refocus e geometria em 16:9/4:3. São eventos sintéticos Godot Linux, não controle físico, Windows nem integração RA real.

Fontes consultadas: OLD privado `94802a16f7a924adeece8b9934c613f0b1529178`, `GameCard` → `LibraryAchievementsPanel` → `AchievementsPanel`, `useGamepadNav` e `services/retroachievements.ts`. Os controles por ícone seguem a instrução mais recente do usuário, não os captions remanescentes no OLD.
