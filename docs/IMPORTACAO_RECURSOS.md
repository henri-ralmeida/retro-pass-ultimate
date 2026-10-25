# Importação e fidelidade do atlas

O atlas editável permanece em `assets/cosmic_console/source_art/raster/master_system_atlas_4k.png`, com 4096×4096 pixels, juntamente com as fontes vetoriais e o Blender. Essa pasta já é excluída da importação automática por `.gdignore`, não do controle de versão.

O recurso consumido pelo GLB conserva seu nome histórico `MasterSystem_Console_master_system_atlas_4k.png`, mas sua entrada de importação agora contém 2048×2048 pixels. Não houve redução adicional da imagem que o aplicativo renderizava: a configuração anterior já limitava a textura importada a 2048 pixels. A nova entrada é uma exportação PNG sem perdas dessa textura efetivamente usada, evitando que cada clone precise decodificar/reprocessar o atlas maior para chegar ao mesmo resultado.

Foi comparada a totalidade dos bytes RGBA, não apenas tamanho de arquivo ou uma captura visual. A textura anterior e a importação nova apresentam o mesmo SHA-256 dos pixels: `75e872aeec388a9f67a5276783303fec9f34d8452d61e4dd54754ffe2c1b03a0`. O registro reproduzível está em `assets/cosmic_console/RUNTIME_ATLAS_IDENTITY.json`. Mipmaps continuam habilitados na configuração de importação.

A importação do editor é serializada com `editor/import/use_multiple_threads=false` para reduzir picos simultâneos de memória. Isso não é uma alegação de melhoria de FPS. A importação limpa foi verificada no Godot 4.6.3; o resultado visual em outra versão/driver ainda requer teste.

Para uma futura alteração das inscrições, edite a fonte 4K/vetorial e gere explicitamente um novo derivado de runtime. Não substitua o original editável pelo derivado 2K.
