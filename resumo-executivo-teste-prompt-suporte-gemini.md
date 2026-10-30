# Resumo executivo: teste de campos de Suporte no Sense com Gemini 3.1

28/10/2026. Detalhes, dados brutos e limites em `resultados-teste-prompt-suporte-gemini.md`.

## Em uma frase

É possível acrescentar a classificação de Suporte (natureza do problema e texto canônico do problema) ao Sense sem mexer no que já existe, por cerca de US$ 11 a mais por mês (+15% sobre a `dim_voc`; sobre a `dim_voc` e os agentes juntos, cerca de 3%, conforme a atualização de 30/10 no `comparativo-ab-vs-sense2-0.md`) e mais uma chamada por ticket do Zendesk. O que o teste não prova é que a classificação acerta, nem que o texto do problema agrupa sozinho.

## O que queríamos saber

1. Dá para extrair natureza, problema canônico e descoberta de funcionalidade com um prompt de Gemini, sem perder a classificação atual (macrotema, tipo, sentimento, categoria)?
2. O texto livre do problema é estável o bastante para contar problemas entre tickets?
3. Quanto custa, e quanto muda o processamento, em comparação com o Sense 2.0 que roda hoje?

## O que foi feito

- 33 tickets do Zendesk de 16 a 27/10: 3 do primeiro teste, 12 do tema "boleto/Pix pago e não baixado" e 18 de tipos variados.
- 4 rodadas em modelos e configurações diferentes. As 2 últimas usaram o modelo de produção, o gemini-3.1-flash-lite.
- Referência de comparação: a classificação gravada hoje na `dim_voc_full_category`.
- Custo do teste inteiro: cerca de US$ 0,5.

## Resultados

**1. Reproduzir o Sense 2.0 funciona, com ressalva.** A chamada A usa o prompt de produção sem alteração. Ela concorda com o gravado em 85% a 88% dos tickets, e as duas repetições saem idênticas nos 33. Os 12% a 15% restantes não vêm do prompt nem de variação entre execuções, e ainda não sabemos a causa.

| Campo | Concordância com o gravado |
|---|---|
| Macrotema | 29/33 (88%) |
| Tipo de incidente | 28/33 (85%) |
| Sentimento | 28/33 (85%) |
| Categorias (conjunto exato) | 28/33 (85%) |

**2. Os campos novos saem bem em uma chamada separada.** A chamada B traz natureza, problema canônico e descoberta de funcionalidade. Nos 33 tickets: 11 bugs, 9 dúvidas, 5 comerciais, 3 gaps, 2 usabilidade, 2 ruído e 1 operacional. Os casos em que o produto funciona como desenhado saem como dúvida, não como bug.

**3. O texto do problema não se repete entre tickets.** Dos 33 tickets, 15 têm problema canônico e os 15 textos são distintos. Os do tema "pagamento não baixado" são próximos entre si, mas não iguais. Contar problemas exige agrupar por similaridade (embeddings), não por igualdade de texto. Isso confirma a análise anterior: esta abordagem é uma etapa intermediária antes da camada semântica.

**4. Uma configuração errada quase invalidou o teste.** Com o gemini-3.1 e `output_schema`, 17 de 66 chamadas falharam e 14 vieram incompletas. Sem `output_schema` (como a produção), 99 de 99 chamadas válidas. Quem for implementar deve manter a chamada sem esse recurso.

## Custo e processamento

Estimativa mensal para os 32.418 itens dos últimos 30 dias, a 4 caracteres por token e com preços de agregadores (US$ 0,25 por milhão de tokens de entrada e US$ 1,50 de saída).

| | Sense 2.0 hoje | Chamada A (R4) | A + B no Zendesk |
|---|---|---|---|
| Custo por ticket do Zendesk | US$ 0,00227 | US$ 0,00227 | US$ 0,00272 |
| Custo por mês | US$ 71,8 | US$ 71,8 | US$ 82,9 (+15%) |
| Chamadas por dia | 1.081 | 1.081 | 1.908 (+77%) |
| Tokens de entrada por dia | 8,9 milhões | 8,9 milhões | 10,2 milhões (+14%) |

- A chamada A custa o mesmo que o Sense 2.0, porque é o mesmo prompt e o mesmo modelo. O ganho dela é de observabilidade (status e validade de cada resposta), não de custo.
- A chamada B soma cerca de US$ 11 por mês. Ela é leve: um sexto dos tokens da A, porque não carrega as ~273 categorias.
- O tempo de execução não foi medido. Fica entre +14% (se o limite for tokens por minuto) e +77% (se for número de chamadas).
- Oportunidades de custo que valem para ambos e não foram aplicadas: deduplicar entradas idênticas (cerca de 26% das chamadas repetem o input) e cache do template (potencial de US$ 72 para cerca de US$ 17, não confirmado no `AI.GENERATE`).

## Riscos e limites

- **Concordância não é acerto.** O gravado não é gabarito e não há rótulo humano nesta amostra. Dois tickets com sentimento diferente (por exemplo "Satisfação" × "Confusão / dúvida") são defensáveis nos dois sentidos.
- **Amostra pequena.** 33 tickets de um único período; diferenças de 2 a 3 tickets estão dentro do ruído.
- **Ambiente de teste.** Rodou no dev, não no endpoint global de produção, o que pode explicar parte da diferença de 12% a 15%.
- **Valores estimados.** Os tokens vêm de uma conversão por caracteres, e os preços de agregadores. Se o modelo cobrasse tokens de pensamento (hipótese não verificada), o custo subiria cerca de US$ 43 por mês.
- **Nada em produção.** Nenhuma tabela foi alterada.

## Recomendação

1. Manter a classificação atual como está (chamada A) e acrescentar os campos novos em chamada separada (B), sem `output_schema`.
2. Não tratar o texto do problema como chave de contagem. Planejar a camada de agrupamento por similaridade.
3. Antes de decidir qualquer troca, medir o acerto com um conjunto rotulado pelo time de Suporte.

## Próximos passos sugeridos

1. Montar um conjunto rotulado (50 a 100 tickets, incluindo os 33 desta amostra) com especialistas de Suporte.
2. Gravar o uso real de tokens e a duração das chamadas para trocar as estimativas por medições.
3. Avaliar o agrupamento do problema canônico por similaridade.
4. Se o conjunto rotulado sustentar, rodar a chamada B em paralelo no Zendesk, sem alterar a `dim_voc_full_category`.
5. Descobrir a causa dos 12% a 15% de diferença rodando a chamada A no endpoint de produção.

## Onde estão os detalhes

- Análise completa: `resultados-teste-prompt-suporte-gemini.md`
- Dados das 4 rodadas: pasta `resultados-teste-prompt-suporte/`
- SQL dos testes: `teste_prompt_suporte_3_tickets.sql`, `teste_prompt_suporte_amostra_comparativo.sql` e `teste_prompt_suporte_amostra_comparativo_v2.sql`
