# Próximas etapas, ainda não concluídas

A implementação atual já contém catálogo local, aplicação de faces disponíveis, caixa articulada e carrossel. As etapas abaixo são requisitos de continuação, não funcionalidades alegadas como prontas.

1. Integrar a identificação online e a obtenção de mídias por um endpoint autorizado e efetivamente validado. Cache por jogo/edição, estados de correspondência incerta, correção manual e ausência de mídia explícita. Não reutilizar chaves de outro aplicativo.
2. Completar a exposição já ligada ao item selecionado: manual real do mesmo jogo quando disponível e, futuramente, sorteio estável por entrada. Controles, cabos, caixa aberta e cartucho assentado são a primeira etapa; nenhuma mídia deve vir de outro jogo.
3. Biblioteca: capas e wheel/logo originais, label correspondente no cartucho, abertura da caixa e acesso aos itens existentes. Nenhuma arte inventada para preencher uma ausência.
4. Leitor de manual integrado ao aplicativo, com páginas reais quando disponíveis. Não abrir um PDF externo como substituto da experiência solicitada, nem inventar páginas.
5. Ao selecionar o cartucho, animação de encaixe no console, sem mãos e sem iniciar emulação.

Windows é o primeiro alvo. Desenvolvimento e testes atuais ocorrem na nuvem Linux; diálogo nativo e execução Windows ainda dependem de teste nessa plataforma. Cada etapa deve preservar o console aprovado e receber teste visual, vídeo real e commit separado coerente.
