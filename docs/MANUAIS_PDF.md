# Manuais PDF locais — etapa parcial, bloqueada por contenção

## Estado (25/10/2026)

**A conversão automática de PDFs arbitrários NÃO está habilitada no app.**
O app informa `pdf_backend_unavailable`, sem abrir/interpretar/hashificar o PDF.
As imagens já suportadas continuam na mesma fila. Não existe download nesta fase.
O aceite do plano continua obrigatório; retomar reavalia o plano e a capability,
sem transformar uma falha anterior em sucesso. Uma tentativa de PDF com identidade
exata remove o overlay anterior daquela superfície, preservando o manual original.

`manual_pdf_service.gd` é a fronteira fail-closed, não um conversor funcionando.
Não há preferência, variável de ambiente, manifesto ou executável em PATH que
habilite parsing em produção. Nenhum binário PDF está incluído na distribuição.
A persistência de vínculos de imagem existente permanece no schema 1; **não há
persistência/retomada de conversão PDF pronta**. O journal persiste a falha explícita.

## Evidência e bloqueio

- O ambiente de diagnóstico possui Poppler `26.05.0`.
- A página oficial <https://poppler.freedesktop.org/> foi verificada em 25/10/2026:
  anuncia `26.10.0` (04/10/2026), incluindo correções de crashes em PDFs malformados.
  A instalação existente não é certificada como backend seguro/atual para usuários.
- Um teste inofensivo de bubblewrap com `--unshare-all` e `/usr/bin/true` falhou:
  `Failed to create NETLINK_ROUTE socket: Operation not permitted`.
  Não se removeu o isolamento para contornar essa restrição.
- Diretório temporário e limite de processos não isolam acesso a arquivos/rede.
  Job Objects no Windows, isoladamente, também não fornecem essa fronteira.
- Poppler contém componentes GPL e outras licenças por arquivo. A instalação
  consultada lista os termos em `/usr/share/doc/poppler-utils/copyright`.
  Antes de redistribuir, revisar a licença do build exato e suas dependências,
  fontes/notices exigidos e política de atualização; não presumir licença permissiva.

Falta um adaptador de backend com versão/build aprovados e isolamento comprovado
para leitura somente do PDF selecionado, escrita somente no cache próprio, rede
negada, memória/CPU/tempo/tamanho limitados e encerramento dos descendentes.
Não se pede para desativar proteções do sistema e não se instala software aqui.

## Contrato preparado, ainda não consumido pela produção

`manual_pdf_manifest.gd` valida candidatos de QA, em leitura somente:

- fonte SHA-256 + ID/versão do backend + opções fixas determinam cache key;
- fonte até 64 MiB; 1–64 páginas, 144 DPI; borda até 4096 px;
- PNG até 8 MiB; conjunto até 128 MiB; manifesto até 64 KiB;
- contagem exata e sequência 1…N, nomes derivados `page-0001.png` etc.;
- todas as páginas são obrigatórias; páginas brancas/idênticas não são removidas;
- dimensões, bytes e SHA conferidos; decode usa os mesmos bytes hashificados;
- caminhos relativos/traversal/symlinks rejeitados; fonte revalidada ao final;
- qualquer falha ou cancelamento devolve zero páginas;
- `backend_security_verified` permanece **false**, mesmo com manifesto válido.

Esse contrato não comprova o número de páginas real de um PDF: a produção futura
precisa obtê-lo pelo backend contido. Não existe publicação atômica de cache PDF
nesta etapa; não confundir gravação do manifesto de diagnóstico com publicação.

## Diagnóstico reproduzível, só dados criados pelo teste

```sh
python3 tools/test_pdf_synthetic_conversion.py
# Opcional: diretório NOVO para conservar evidência e inspeção do livro:
python3 tools/test_pdf_synthetic_conversion.py --output /tmp/pdf-qa-novo
```

O script não aceita PDF de entrada, instala nada ou habilita a capability. Cria
seu próprio PDF: página retrato, página branca, página landscape. Usa argumentos
em vetor e timeout para os processos diagnósticos. Verifica conversão real,
ordem/branco/orientação, fonte imutável, além de encrypted/corrupt/header inválido
criados pelo próprio teste. Dependências externas: Poppler, ReportLab, Pillow.
Não é sandbox e não deve ser adaptado para abrir documentos arbitrários.

Os testes Godot `test_manual_pdf_boundary.gd` e `test_manual_pdf_manifest.gd`
cobrem contrato, fila, consentimento, rollback, retomada da falha, cancelamento,
identidade/cache, páginas ausentes/reordenadas/duplicadas e symlink. Os PNGs do
teste de schema são sintéticos diretos; não são prova de conversão PDF.
O diagnóstico Python separado e a captura do livro usam PNGs realmente rasterizados
do PDF sintético, claramente identificados. Não são documentos pessoais.

## Ainda não verificado/implementado

- backend contido e atualização/distribuição segura Linux/Windows;
- conversão PDF produtiva com progresso/cancelamento do processo/retomada;
- publicação atômica, recuperação após crash/disk-full e limpeza de staging próprio;
- persistência PDF versionada com fonte + páginas revalidadas no restart;
- timeout/cancelamento contra parser malicioso ou documentos arbitrários;
- teste no Windows do usuário.

O import limpo do projeto também tem limitação anterior exit 137 no cloud;
uma execução `RETROPASS_SKIP_IMPORT=1` é **tests-only**, não clean import PASS.
