# Resultados do teste: prompt de produção (Sense 2.0) × campos novos de Suporte, em 33 tickets

Data da análise: 28/10/2026. Complementa a seção 8 de `sense-reformulacao-regras-suporte-no-gemini.md`, que registrava o teste como "não executado". Os dados brutos das 4 rodadas estão em `resultados-teste-prompt-suporte/` (ver seção 9).

## 1. Pergunta e resumo

**Pergunta.** Dá para extrair, com um prompt de Gemini, os campos novos do Suporte (`natureza`, `problema_canonico`, `descoberta_feature`, `evidencia`) sem perder a classificação que o Sense 2.0 já grava (macrotema, tipo de incidente, sentimento, categoria)? E o texto livre do `problema_canonico` é estável o bastante para contar problemas?

**Resposta curta.**

1. Com o prompt de produção sem alteração e gemini-3.1, o replay reproduz entre 85% e 88% do gravado. As repetições são idênticas (33/33), então a diferença de 12% a 15% não é nondeterminismo.
2. Os campos novos funcionam melhor em uma chamada separada. Dentro do prompt de produção, eles empurram tipo e sentimento para Incidentes/Insatisfação (rodada 2).
3. O `problema_canonico` ficou legível e discrimina bem os casos diferentes, mas nenhum texto se repete entre tickets (15 textos em 15 tickets). Agrupar exige embeddings ou normalização.
4. A concordância mede semelhança com o gravado, não acerto. Não há rótulo humano nesta amostra.
5. Falhas em massa na rodada 3 vieram da chamada com `output_schema` no 3.1. A rodada 4, sem `output_schema`, teve 99/99 chamadas válidas.

## 2. Amostra

33 tickets Zendesk com `llm_send_status = enviado_llm`, `nk_event_date` de 16 a 27/10/2026, fonte `contaazul-ssbi.gold_strategy.dim_voc_full_category`. Ids fixos, na ordem em que estão no SQL.

| Grupo | Tickets | Critério |
|---|---|---|
| O | 3 | Tickets do primeiro teste: 6189021, 6188174, 6178426 |
| A | 12 | Tema "boleto/Pix pago e não baixado", por regex no resumo. 7 acertos reais e 5 falsos positivos (6212390, 6191974, 6182188, 6191979, 6206529) mantidos como controle |
| B | 18 | 3 por tipo de incidente (Dúvida, Incidentes, Reclamação, Ajustes, Sugestão, Elogio), fora do tema A |

A classificação gravada de cada ticket está em `00_producao_gravado.json`.

## 3. Rodadas executadas

| # | SQL | Modelo | Chamada | O que mudou | Resultado |
|---|---|---|---|---|---|
| 1 | `teste_prompt_suporte_3_tickets.sql` | gemini-2.5-flash-lite | 1 prompt novo (lista filtrada, 1 categoria, natureza + postura) | 3 tickets × 3 reps | Reps idênticas; categorias diferentes do gravado |
| 2 | `teste_prompt_suporte_amostra_comparativo.sql` (v1) | gemini-2.5-flash-lite | replay + híbrido, com `output_schema` | 33 tickets | Sem falhas; replay concorda pouco com o gravado |
| 3 | v1 (mesmo SQL) | gemini-3.1-flash-lite | replay + híbrido, com `output_schema` | Troca de modelo | 17/66 `Failed to parse`, 14 incompletas |
| 4 | `teste_prompt_suporte_amostra_comparativo_v2.sql` | gemini-3.1-flash-lite | A (2 reps) + B, sem `output_schema` | Duas chamadas, `responseMimeType` JSON | 99/99 válidas |

Parâmetros comuns: temperatura 0, `thinking_budget` 0, `maxOutputTokens` 2000, `connection_id us.vertex_connection`. Em produção o modelo é `gemini-3.1-flash-lite` (contexto do Sense e doc de arquitetura).

**Rodada 1.** Prompt de 13 a 20 mil caracteres, contra 34 a 41 mil em produção, porque a lista de categorias foi filtrada. A produção pede várias categorias separadas por `|`; o teste pedia uma. Custo informado: 101 MB.

## 4. Resultados

### 4.1 Rodada 1: estabilidade e primeira comparação (3 tickets)

As 3 repetições saíram idênticas em todos os campos nos 3 tickets (temperatura 0, mesmo input). Isso mede repetibilidade, não estabilidade entre tickets diferentes do mesmo problema.

| Ticket | Categoria (teste) | Categoria gravada | Tipo (teste → gravado) |
|---|---|---|---|
| 6178426 | Cobrança - Vencidos / Inadiplentes / cálculo automático | Régua / Envio de cobrança \| Extrato/Conciliação/Integração - UX | bug → Reclamação |
| 6188174 | `Financeiro` (rótulo truncado, não existe em produção) | Financeiro - outras melhorias | bug → Dúvida |
| 6189021 | Cobrança - Vencidos / Inadiplentes / cálculo automático | Régua / Envio de cobrança | bug → Incidentes |

Achados: a postura `insatisfação` está fora do vocabulário pedido; `descoberta_feature` veio preenchida em tickets de bug; `bug` no 6188174 é discutível (a baixa automática só vale para boleto da Conta PJ, é regra de negócio).

### 4.2 Rodada 2: gemini-2.5, replay e híbrido (33 tickets)

Concordância com o gravado, somando O, A e B (derivada dos percentuais do resumo × número de tickets):

| Campo | Replay | Híbrido |
|---|---|---|
| Macrotema | 28/33 (85%) | 28/33 (85%) |
| Tipo de incidente | 19/33 (58%) | 21/33 (64%) |
| Sentimento | 19/33 (58%) | 16/33 (48%) |
| Categorias, conjunto exato | 13/33 (39%) | 15/33 (45%) |

- O gravado atribui "Satisfação" a 12 tickets; o replay manteve só 4 deles. Em 8 trocou, quase sempre para "Confusão / dúvida". Isso indicou diferença de modelo, o que a rodada 4 confirmou.
- No híbrido, 18 de 33 tickets saíram como bug, incluindo casos em que o produto funciona como desenhado (6188174, 6192237, 6203133, 6182188).
- O bloco novo mexeu nos campos legados: o tipo mudou em cerca de 14 tickets em relação ao replay, a maioria rumo a Incidentes ou Reclamação.
- No replay, as colunas `natureza`, `problema_canonico` e `descoberta_feature` são lixo (o prompt de produção não as pede e o `output_schema` obrigou o modelo a inventar valores).
- No híbrido, os grupos A e O tiveram 11 tickets com `problema_canonico` preenchido e 11 textos distintos: nenhum texto repetido.

### 4.3 Rodada 3: gemini-3.1 com `output_schema` (falhas)

| Situação | Replay | Híbrido |
|---|---|---|
| 5 campos completos | 22/33 | 8/33 |
| `Failed to parse the response` | 7 | 10 |
| Parcial (só macrotema e tipo; resto nulo, status vazio) | 4 | 10 |
| Tipo inválido (lista de opções ou texto de raciocínio no campo) | 0 | 5 |

- 13 dos 33 tickets falharam em pelo menos uma variante; 4 falharam nas duas (6178426, 6192237, 6212743, 6219033). A produção gravou valores para os 33, então a causa está na chamada, não nos tickets.
- O resumo colado nessa rodada engana: `AVG` ignora NULL. O "100% de sentimento" do híbrido vem de 8 tickets (7 acertos em 8).
- Nas linhas completas do replay, a concordância com o gravado foi maior que no 2.5: macrotema 25/26, tipo 23/26, sentimento 19/22, categoria exata 15/22 (derivado, sobre as linhas válidas).
- Em 6202245 o campo tipo do híbrido veio com um parágrafo de raciocínio com a resposta inteira.

### 4.4 Rodada 4: gemini-3.1 sem `output_schema` (v2)

**Estabilidade e falhas.** 99/99 chamadas com status de API vazio e JSON válido. A_rep1 e A_rep2 idênticas em macrotema, tipo, sentimento e categorias nos 33 tickets. Tamanho médio da resposta: 406 caracteres (A) e 199 (B), longe do limite de 2000 tokens. `finish_reason` veio nulo (o caminho JSON do SQL para lê-lo estava errado).

**Concordância da chamada A com o gravado** (somando os 3 grupos):

| Campo | Concordância |
|---|---|
| Macrotema | 29/33 (88%), contado nas linhas do detalhe |
| Tipo de incidente | 28/33 (85%) |
| Sentimento | 28/33 (85%) |
| Categorias, conjunto exato | 28/33 (85%) |

Divergências por campo:

- **Tipo** (6199844, 6212390, 6194451, 6205869, 6218479): em 4 o replay vai para Incidentes ou Reclamação; no 6194451 troca Elogio por Dúvida.
- **Sentimento** (6192237, 6206529, 6205869, 6188174, 6189021): em 4 o gravado diz "Satisfação" e o replay "Confusão / dúvida"; no 6189021, Raiva → Insatisfação. O padrão é sistemático, o que sugere outra versão do modelo, outra região do endpoint ou outra data de execução na produção. Não foi possível separar as causas.
- **Categoria** (6192237, 6199844, 6210991, 6216173, 6189021).
- **Macrotema** (6191974, 6191979, 6199844, 6206529).

**Campos novos (chamada B).** Natureza dos 33 tickets: 11 bug, 9 dúvida, 5 comercial, 3 gap, 2 usabilidade, 2 ruído, 1 operacional. Os casos em que o produto funciona como desenhado agora saem como dúvida (6188174, 6192237, 6203133, 6203002). Defeitos de regra: 6197574 saiu como bug sem `problema_canonico`; a evidência de 6203002 tem 16 palavras (limite 15). Classificações discutíveis: `ruído` em 6194451 e 6206640 e `usabilidade` em 6191979.

**`problema_canonico`.** 15 tickets têm texto e os 15 textos são distintos. Tema "pagamento não baixado":

| Ticket | Texto |
|---|---|
| 6189021 | Pagamento de boleto não baixado automaticamente |
| 6199844 | Pagamento de boleto não baixado automaticamente no sistema |
| 6213525 | Pagamento de boleto via cartão de crédito não baixado automaticamente no sistema |
| 6210991 | Pagamento via Pix não foi compensado automaticamente no sistema |
| 6178426 | Pagamento via Pix em boleto não baixou a parcela nem entrou na conta |

6189021 e 6199844 diferem só por "no sistema". Os falsos positivos do regex (TED devolvido, titularidade, baixas manuais, boleto já baixado) ficaram com textos próprios ou vazios.

**Categoria, tema "pagamento não baixado".** O replay da rodada 4 espalha os tickets do mesmo problema por Vencidos / Inadimplentes (6199844, 6210991, 6213525, 6189021), Boleto Registrado para outros bancos (6193722), Extrato/Conciliação UX (6203002, 6203133), Régua + Extrato (6178426) e Financeiro - outras melhorias (6188174). O gravado também é disperso, então a categoria não identifica o problema.

## 5. Conclusões

1. **Mantenha a chamada A como está hoje.** As colunas legadas vêm do prompt de produção sem alteração. Os 12% a 15% de diferença para o gravado não se resolvem ajustando o prompt, que é idêntico.
2. **Campos novos em chamada separada (B).** No ticket 6189021, o prompt B tem cerca de 6 mil caracteres, contra 34 mil do A, porque não carrega a lista de 273 categorias. O custo extra de entrada é da ordem de 18% do A. O custo mensal não foi recalculado.
3. **Não use `output_schema` com o 3.1.** O que a rodada 4 mudou em relação à 3 foi tirar o `output_schema` e adicionar `responseMimeType`. Não sei qual dos dois resolveu; a produção não usa `output_schema`.
4. **Texto livre não agrupa por igualdade.** O `problema_canonico` precisa de embeddings ou normalização. Isso sustenta a conclusão da seção 9 do documento principal ("etapa curta antes da camada de embeddings").
5. **Falta um golden set.** Concordância não é acerto. Divergências como Satisfação × Confusão em dúvida resolvida são defensáveis nos dois sentidos.

## 6. Limites

- Amostra de 33 tickets de um único período. Diferenças de 2 a 3 tickets estão dentro do ruído.
- As 3 repetições de cada chamada são idênticas por construção (temperatura 0), então não medem variação entre execuções em momentos diferentes.
- Não foi possível rodar no endpoint global da produção (projeto `contaazul-datalake-prod`). O teste usou `us.vertex_connection` no dev.
- Os percentuais da rodada 2 e os de macrotema da rodada 4 foram derivados a partir dos resultados colados (percentual × tickets ou contagem das linhas); não vieram direto do BigQuery.
- Os campos de texto longo (`resumo`) não foram guardados nos JSONs.
- A origem dos erros de `output_schema` na rodada 3 é inferida, não verificada: o `finish_reason` não pôde ser lido.

## 7. Correções a afirmações anteriores

- Na análise da rodada 3, eu disse que `Valor do plano` não é rótulo canônico. A validação por linha exata (rodada 4) aprovou, então ele existe na lista do prompt. O gravado usa `Percepção de Custo-Benefício` nos tickets 6202245 e 6216173.
- Eu disse que a hipótese de truncamento (limite de 2000 tokens) explicava as falhas da rodada 3. A rodada 4 usou o mesmo `maxOutputTokens` e as respostas tiveram em média 406 caracteres, então truncamento não explica.
- Eu disse que a lista do SELECT 4 da rodada 4 tinha 14 textos. Tem 15 (ver 4.4).
- Eu disse que, nas divergências de tipo da rodada 4, 3 tickets iam para Incidentes ou Reclamação. São 4 (ver 4.4).

## 8. Próximos passos sugeridos

1. Montar um golden set rotulado por especialistas de Suporte (50 a 100 tickets, incluindo os 33 desta amostra) para medir acerto.
2. Medir o `problema_canonico` por similaridade (embeddings) e definir limiares de agrupamento.
3. Se for possível, repetir a chamada A no endpoint global de produção para fechar a diferença de 12% a 15%.
4. Adicionar validações pós-chamada: bug sem `problema_canonico`, evidência acima de 15 palavras, categoria fora da lista (marcar para nova tentativa).
5. Atualizar a seção 8 do documento principal com o link para este arquivo.

## 9. Arquivos

SQL (raiz do repositório):

- `teste_prompt_suporte_3_tickets.sql` (rodada 1)
- `teste_prompt_suporte_amostra_comparativo.sql` (rodadas 2 e 3)
- `teste_prompt_suporte_amostra_comparativo_v2.sql` (rodada 4)

Dados em `resultados-teste-prompt-suporte/`:

| Arquivo | Conteúdo |
|---|---|
| `00_producao_gravado.json` | Classificação gravada do Sense 2.0 para os 33 tickets |
| `01_rodada1_gemini-2.5_3tickets.json` | Resultados da rodada 1 (reps idênticas agrupadas) |
| `02_rodada2_gemini-2.5_v1_33tickets.json` | Resumo, `problema_canonico` e detalhe por ticket |
| `03_rodada3_gemini-3.1_v1_33tickets.json` | Resumo, contagem por status e detalhe com falhas |
| `04_rodada4_gemini-3.1_v2_33tickets.json` | Diagnóstico, concordância, autoconsistência, `problema_canonico` e detalhe |

Convenções dos JSONs: valores numéricos e booleanos foram convertidos de texto para número/booleano; em `categorias`, o texto devolvido pelo modelo está separado por ` | ` quando há mais de uma categoria; os campos de texto longo (`resumo`) foram omitidos; as colunas sem valor analítico do replay da rodada 2 foram omitidas.
