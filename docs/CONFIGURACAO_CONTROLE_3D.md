# Configuração contextual do controle Master System

Clique curto no controle P1/P2 da exposição ou abra F1 → Master System → Jogador. O painel amplia outra instância do mesmo modelo, sem alterar a HOME ou seus materiais. Direções e botões podem ser selecionados na geometria ou na lista equivalente. Pause permanece na lista P1, identificado como botão do console.

## Capturar e salvar

- Escolha teclado ou controle e o jogador. Para gamepad, identifique explicitamente o dispositivo; outro dispositivo não assume sua captura.
- Selecione um comando, solte a entrada que abriu a captura e pressione/solte a nova entrada. Esc/F1 ou Cancelar interrompem a captura.
- Uma colisão com outro comando oferece trocar ou cancelar. Teclas compartilhadas entre P1/P2 exigem escolha explícita antes de salvar.
- Salvar altera apenas perfis de comandos do Master System. X/Z/I e demais atalhos da interface continuam no arquivo separado de controles da interface.
- Voltar com rascunho oferece salvar, descartar ou continuar. Perder foco interrompe a captura sem apagar o rascunho. Desconexão não troca silenciosamente o dispositivo.
- Testar entradas ilumina comandos reconhecidos, sem executar jogo ou emulador. Z e o botão leste continuam testáveis. Esc/F1 ou o botão visual encerram; no gamepad, segurar o cancelamento identificado por 0,8 s mostra progresso e encerra, exigindo soltura antes de voltar.

## Armazenamento e limites

Os perfis ficam em `user://input/gameplay/master_system/`, em gerações JSON validadas, com retenção de oito gerações válidas. Gravação usa temporário e renomeação para um nome novo; versões inválidas são preservadas para diagnóstico. O arquivo `controls.cfg` da interface não é alterado. Não há garantia de durabilidade em falha elétrica; um bloqueio abandonado após crash exige diagnóstico, não é removido automaticamente.

Botões de pads não reconhecidos podem ser identificados explicitamente. Seus eixos não são aceitos sem calibração, que ainda não foi implementada. Símbolos manuais não comprovam a identidade do hardware. Não existe vínculo com core de emulação nesta etapa.

Testes automatizados usam entradas sintéticas. Persistência foi exercitada entre processos Linux; Windows, controles físicos, Steam Input, USB/Bluetooth e leitores de tela ainda exigem validação específica.

## Regressão de navegação durante teste

Enquanto Testar entradas está ativo, Voltar e troca de jogador não enfileiram navegação. Encerre o teste explicitamente antes de sair; salvar depois disso não fecha o painel por um clique anterior ignorado. A regressão automatizada inclui rascunho e gravação posterior. O teste de layout verifica alcance por rolagem dos comandos/conflitos de P1/P2 em 1152×648, 1024×768 e 800×600, sem confundir geometria headless com pixels renderizados.
