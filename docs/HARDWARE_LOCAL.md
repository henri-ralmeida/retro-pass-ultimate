# Recursos de hardware locais

O repositório público contém uma variante neutra do controle. As estampas e fotografias do protótipo anterior não são incluídas automaticamente na distribuição pública. A restauração visual local conserva a geometria, as UVs e os materiais desse recurso original; isso não estabelece uma licença de redistribuição das fotografias.

Para usar um recurso próprio ou autorizado, coloque o GLB na pasta ignorada `assets/local_hardware_art/`. Crie nessa pasta `manifest.json` com o campo `controller_model` contendo somente o nome do arquivo GLB, sem caminhos externos ou URL. O protótipo não pesquisa outras pastas nem baixa modelos.

Exemplo:

```json
{"controller_model":"meu_controle.glb"}
```

O recurso precisa manter o nó `ControllerCableAnchor` e o eixo local X indicando a saída do cabo. O GLB da restauração REV2 usa as medidas nativas em metros. Na ausência de um manifesto válido, o aplicativo conserva o recurso neutro público, sem afirmar que é a aparência original completa.

Não versione esta pasta, capas, fotos pessoais ou credenciais. Arquivos locais não são enviados à rede pelo carregador.
