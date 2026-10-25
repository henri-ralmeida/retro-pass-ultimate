# Mídias locais persistentes e tour opcional

## O que esta fase faz

- Mantém **vínculos exatos**, não uma cópia modificada do catálogo de origem, em `user://retropass_media_bindings.json`.
- Após o início, revalida em worker somente os arquivos anteriormente aprovados: sistema, ID, variante/edição, assinatura dos metadados, caminho relativo, SHA-256 e decodificação limitada. Não busca arquivos novos, não varre pastas e não acessa ROMs.
- Um catálogo alterado durante o worker invalida a aplicação inteira. Um arquivo alterado, ausente, ambíguo ou symlink não é reaplicado. Revalidar uma superfície já aplicada com falha restaura sua referência original e invalida cache.
- Salva overlay antes de aplicar: falha de gravação não é anunciada como persistência bem-sucedida. A gravação usa temporário, flush, rotação para `.bak` e rename; leitura ignora `.tmp` e recupera backup estruturalmente válido.
- A configuração/consentimento e a fila continuam separados do overlay. Nenhuma credencial é salva nele. Arquivos privados e seus backups não devem entrar no Git.

O adaptador reconhece explicitamente `system_id: atari2600` como `atari_2600`; campos de sistema contraditórios são rejeitados. Isso **não cria** referências de mídia inexistentes no catálogo Atari e não infere nomes de texturas/GLBs.

## Categorias e limites honestos

Capas/labels e wheel preservam seus campos próprios. Imagens genéricas, screenshots, títulos, mapas e afins ficam em campos `media_*`; **não são promovidas a capas** e esta fase não cria uma galeria para exibi-las.

Um `manual` explicitamente associado a uma imagem PNG/JPEG válida pode preencher `manual_pages` com **uma página**, com ID do jogo explícito, limite de 8 MiB e 4096 px por aresta. Não inventa ordem de páginas nem sobrescreve um ID de manual contraditório. **PDF continua sem conversão**; download online não está implementado nesta fase.

A assinatura valida a continuidade da associação declarada, não a autenticidade da arte/edição. Um SHA correto não muda `identity_status: unverified`. A revalidação ocorre no processamento e a cada reinício, não é monitoramento contínuo do filesystem: o renderizador existente ainda lê caminhos locais; editar um arquivo depois da validação exige nova revalidação.

O overlay tem limite de 4096 vínculos e 16 MiB de JSON. SHA conflitantes para o mesmo caminho são rejeitados, em vez de reutilizar validação de outro vínculo. O arquivo privado não é um cofre assinado contra um usuário local malicioso; não o importe de terceiros.

## Tour

`user://retropass_media_tour.json` mantém versão e estado: `unseen`, `in_progress`, `configured`, `skipped` ou `later`.

A oferta automática espera a tela inicial estável e sem modal concorrente. Mostrar o tour não inicia leitura de mídia/download. Revisar e confirmar o **plano atual** é obrigatório para novo processamento. Pular, configurar depois ou fechar não provoca insistência; um tour interrompido em `in_progress` também não reabre automaticamente após crash. O ícone de mídia permite reabrir sempre. Ações são ícones com tooltip e nome acessível, sem legendas de botão visíveis.

Perfis que já tinham decisão/plano não recebem uma nova oferta intrusiva. A variável `RETROPASS_DISABLE_AUTOMATIC_TOUR=1` suprime só a oferta automática (útil para QA/kiosks); não elimina confirmação nem desativa o ícone. A suíte geral usa essa variável; `test_media_first_use_tour.gd` testa o fluxo automático diretamente.

## Verificação reproduzível

- `cosmic/test_media_binding_store.gd`: schema, backup/crash, SHA, catálogo/sistema/variante, symlink, manual, worker, cancelamento tardio e rollback.
- `cosmic/test_media_host_restore.gd`: espera por estabilidade, serialização, aplicação única e rejeição de catálogo alterado durante worker.
- `cosmic/test_media_first_use_tour.gd`: estados, foco, ícones, pular/depois, interrupção e reabertura.
- `cosmic/test_media_binding_restart.gd -- write|restore|recover|reject_changed`: quatro processos distintos com o mesmo `XDG_DATA_HOME` isolado.
- `tools/verify_project.sh`: integra esses testes à suíte existente. `RETROPASS_SKIP_IMPORT=1` é **tests-only**, não um PASS de importação limpa.

Todos os dados desses testes são fictícios/sintéticos. Windows, mídia do usuário, PDF convertido e provedores online exigem validação separada; não foram implicitamente aprovados por estes testes.
