# Cenário A + B × Sense 2.0: volume, tempo, tokens, custo e assertividade

28/10/2026. Consolida `resultados-teste-prompt-suporte-gemini.md` (teste de 33 tickets) e `simulacao-dia-2026-10-19-sense2-vs-ab.md` (dia completo, 19/10). Dados brutos em `resultados-teste-prompt-suporte/`.

> **Atualização de 30/10/2026.** Três correções, sem alterar os números medidos abaixo:
>
> 1. **Base de custo parcial.** O "Sense 2.0 total" (US$ 4,88/dia e US$ 128,5/mês) soma só a `dim_voc` (A) e o agente de Suporte V2. Pela DB de Logs (29/09 a 29/10), os agentes custam ~US$ 360/mês (Onboarding ~63%, Suporte ~26%, Cross ~9%). Somando os ~US$ 72 da `dim_voc`, a base é de ~US$ 430, e os US$ 11/mês da chamada B equivalem a cerca de 3% (conta minha, sobre estimativas), não a 8,6%.
> 2. **Populações diferentes.** A chamada B classifica tickets do Zendesk (1.215 em 19/10). O teste AUX-S classifica conversas do Intercom com resumo (1.961 em 19/10, das quais a V2 lê 707). As duas tratam do Suporte e não são a mesma entrega; os documentos não as somam, e escolher uma ou definir como convivem é decisão pendente. O Intercom não é fonte da `dim_voc`.
> 3. **Tempo.** O job de 2,125 s segue sem identificação do comando. O board do Miro cita ~30 s para o Gemini classificar 1.254 conversas no BigQuery (teste AUX-S); são medições diferentes.

Etiquetas usadas nas tabelas: **[medido]** vem do BigQuery ou de um job rodado; **[log]** vem do log de execução do agente no Notion; **[doc]** vem dos documentos do projeto; **[est.]** é estimativa minha (4 caracteres por token; US$ 0,25 por milhão de tokens de entrada e US$ 1,50 de saída no Gemini 3.1 Flash-Lite, preços de agregadores; US$ 6,6 por milhão de tokens mistos para o agente, convenção do time).

## 1. Leitura rápida

1. **A + B ficam 8,6% a 11% mais caros que o Sense 2.0 de hoje, sobre uma base parcial (ver a atualização de 30/10 acima)** (US$ 5,42 contra US$ 4,88 no dia 19/10; US$ 139,6 contra US$ 128,5 por mês, se o agente V2 for mantido).
2. **Em volume, A + B estrutura 1.215 tickets do dia, um a um**, contra 705 conversas classificadas pelo agente de Suporte em um universo de 2.728. A + B alcança 391 tickets que o agente não vê (66 deles N2/N3).
3. **O job informado (2,1 s) indica que a chamada B para o dia inteiro é rápida**, mas é uma única medição e eu assumi que é o job da B (ver seção 4).
4. **Assertividade comparada:** a chamada A reproduz 85% a 88% do que o Sense 2.0 grava. Os campos novos (B) não têm equivalente por ticket no Sense 2.0, e nem um lado nem outro tem acerto medido contra rótulo humano.
5. **A troca é parcial.** A + B substituem a classificação por conversa do agente. Não substituem clusterização, tendência, escala e resolução, nem a leitura das conversas retidas pelo bot.

## 2. O que está sendo comparado

| | Sense 2.0 hoje | A + B |
|---|---|---|
| Classificação populacional | Prompt A (macrotema, tipo, sentimento, categoria, resumo) em `dim_voc_full_category`, todas as fontes | Igual: o prompt A não muda |
| Suporte | Agente V2: lê o resumo de IA das conversas do Intercom, classifica por amostra e agrupa em sinais no Notion | Chamada B por ticket do Zendesk: natureza, problema canônico, descoberta de funcionalidade e evidência |
| Modelo | gemini-3.1-flash-lite (A); Claude (agente) | gemini-3.1-flash-lite nas duas chamadas |
| Colunas `domain`, `subdomain`, `is_atendimento` | Só existem na cópia do Erick no dev | Derivadas por mapa de categoria (seção 7.4) |

## 3. Volume analisado

**Dia 19/10/2026 (segunda):**

| | Sense 2.0: agente V2 | Sense 2.0: `dim_voc` (A) | A + B |
|---|---|---|---|
| Base | 2.728 conversas do Intercom [log] | 1.523 itens, todas as fontes [medido] | 1.215 tickets do Zendesk (1.349 linhas ticket-categoria) [medido] |
| Analisados um a um | 705 (26%) [log] | 1.523 (100%) | 1.215 (100%); 1.017 com transcrição (84%) |
| Selecionados | 934: censo N2/N3 102 + censo muito negativo 38 + amostra de 30% com 794 | — | — |
| N2/N3 vistos | ~102 | 165 | 165 |
| Fora do Intercom (web/e-mail ou sem conversa) | 0 | 391 | 391 |
| Conversas retidas pelo bot (sem ticket na dim) | 1.664 na base, vistas por amostra | 0 | 0 |

A `dim_voc` do dia: Zendesk 1.215, aquisição 175, NPS 90, Keys-Off 42, portal de ideias 1.

**Como ler 705 × 1.215.** Não é o mesmo universo, e o Intercom não entrou na `dim_voc` como fonte (não existe `source = 'intercom'`).

- Os 705 do agente são conversas do Intercom, amostradas (26% de 2.728), lidas pelo resumo de IA de ~156 caracteres.
- Os 1.215 são todos os tickets do Zendesk do dia, lidos pela transcrição (contexto médio de ~4 mil caracteres).
- Dos 1.215, 824 (68%) nasceram de uma conversa do Intercom que transbordou para um ticket (a transcrição do ticket inclui a etapa do bot); os outros 391 (32%) vieram de web/e-mail ou não têm conversa registrada.
- Das 2.728 conversas, só 824 (30%) viraram ticket na `dim_voc`. As outras 1.904 (70%, quase todas resolvidas pelo bot) não aparecem em A + B.

**Mês (30 dias até 27/10):** 32.418 itens na `dim_voc`, dos quais 24.814 do Zendesk [medido]. O agente tem 24 execuções logadas de 28/09 a 26/10 [log].

## 4. Tempo de execução

| | Sense 2.0: agente V2 | Sense 2.0: `dim_voc` (A) | A + B (chamada B) |
|---|---|---|---|
| Medição | 1.500 s (25 min) em 19/10; as 9 execuções com duração registrada vão de 952 a 1.500 s [log] | "Minutos" por run, sem medida [doc] | **2,125 s decorridos, 7,076 s de slot, 31,77 MB embaralhados, 0 B para disco** [job informado por você] |
| O que está incluído | Orquestração do agente: 700 chamadas de ferramenta, clusterização, síntese de 50 sinais, escrita no Notion | Chamada do LLM e gravação incremental | Chamada ao LLM em 1.215 tickets (assumido) |

- **Assumi que o job é o da chamada B.** Se for outro comando do script (população, mapa do Erick ou uma das consultas), esta seção muda.
- Se for a B, a vazão foi de cerca de 570 chamadas por segundo (1.215 / 2,125 s), muito acima das hipóteses de 2 a 20 chamadas por segundo que usei antes. Aquelas hipóteses eram pessimistas.
- A chamada A tem cerca de 5,7 vezes mais tokens de entrada por ticket (8.479 contra 1.489). Se o gargalo for tokens, a A do dia levaria da ordem de 12 s; isso é extrapolação minha, não medição.
- Os 25 minutos do agente incluem trabalho que a B não faz (agrupar, sintetizar, escrever no Notion), então os dois tempos não são comparáveis um a um.
- Uma medição, em dia útil e no dev. Em produção a vazão depende da cota do projeto e de outros jobs.

## 5. Tokens (estimativa)

| Dia 19/10 | Entrada | Saída |
|---|---|---|
| Agente V2 (Claude, tokens estimados no log) | 225 mil no total | — |
| Sense 2.0 `dim_voc`: prompt A, 1.523 itens [est.] | 12,6 milhões | 155 mil |
| Chamada B, 1.215 tickets [est.] | 1,8 milhão | 61 mil |
| **A + B** | **14,4 milhões (+14%)** | 216 mil |

Mês (30 dias): A em todas as fontes 267,5 milhões de entrada e 3,3 milhões de saída; B 36,9 milhões e 1,2 milhão [est.]. O agente V2 consumiu cerca de 8,6 milhões de tokens nas 24 execuções logadas [log]. Os tokens do agente (Claude) e do Gemini não são comparáveis um a um, porque custam preços muito diferentes.

A estimativa usa a média de 30 dias do tamanho dos prompts por fonte (Zendesk: 33.917 caracteres; contexto de 4.010). A coluna de resposta do SQL não gravou `usageMetadata`, então não há contagem real de tokens.

## 6. Custo (estimativa)

| | Dia 19/10 | Mês (30 dias) |
|---|---|---|
| Sense 2.0: `dim_voc` (A) | US$ 3,39 | US$ 71,8 |
| Sense 2.0: agente V2 | US$ 1,49 [log] | US$ 56,7 (24 execuções) [log] |
| **Sense 2.0 total** | **US$ 4,88** | **US$ 128,5** |
| Chamada B (1.215 tickets no dia) | + US$ 0,54 | + US$ 11,1 |
| **A + B, com o agente V2 mantido** | **US$ 5,42 (+11%)** | **US$ 139,6 (+8,6%)** |
| A + B sem contar o agente | US$ 3,93 (+16% sobre a A) | US$ 82,9 |

- O custo do agente nos logs vai de US$ 0,59 a US$ 6,93 por execução (média de US$ 2,36); é auto-estimado pelo próprio agente.
- O dia 19/10 foi de volume acima da média (1.523 itens contra ~1.081 por dia no mês).
- Os cerca de US$ 135 por mês do documento principal vinham de uma estimativa a partir da primeira execução do agente (US$ 4,55); os logs de 28/09 a 26/10 somam US$ 56,7.
- Não incluem: camada de agrupamento por embeddings, cache do template (potencial de queda da A, não confirmado no `AI.GENERATE`) nem dedupe de entradas repetidas.
- Se o modelo cobrasse tokens de pensamento (hipótese não verificada), o custo sobe cerca de US$ 43 por mês.

## 7. Assertividade comparada com o Sense 2.0

**Nenhum dos lados tem acerto medido contra rótulo humano.** O que existe é concordância e coerência.

### 7.1 Chamada A × o que o Sense 2.0 grava (teste de 33 tickets) [medido]

| Campo | Concordância |
|---|---|
| Macrotema | 29/33 (88%) |
| Tipo de incidente | 28/33 (85%) |
| Sentimento | 28/33 (85%) |
| Categorias (conjunto exato) | 28/33 (85%) |
| Repetições idênticas | 33/33 |
| JSON válido | 99/99 |

O prompt é o mesmo, então a diferença de 12% a 15% não vem do prompt nem de variação entre execuções. A causa não está isolada (pode ser versão do modelo ou endpoint: o teste rodou no dev).

### 7.2 Chamada B: coerência da natureza com o tipo gravado (33 tickets) [medido]

| Tipo gravado | Natureza da B | Coerente? |
|---|---|---|
| Incidentes (7) | bug 6, dúvida 1 | 6/7 |
| Sugestão (3) | gap 3 | 3/3 |
| Elogio (3) | comercial 2, ruído 1 | 3/3 (não-produto) |
| Dúvida (10) | dúvida 7, bug 1, comercial 1, usabilidade 1 | 7/10 |
| Ajustes (5), Reclamação (5) | espalhadas | sem correspondência um a um |

Nos 23 tickets com correspondência natural, 19 (83%) são coerentes. É coerência, não acerto: a natureza foi desenhada para separar o que o tipo mistura.

### 7.3 Dia completo: natureza × nível do ticket no Zendesk (1.215 tickets) [medido]

| Nível | Tickets | Natureza bug | Natureza dúvida |
|---|---|---|---|
| N3 (Incidente) | 12 | 7 (58%) | 1 |
| N2 (Ajustes) | 153 | 77 (50%) | 5 |
| N1 (Dúvida) | 1.034 | 229 (22%) | 246 (24%) |

Regras da B: JSON válido em 1.215/1.215; 2 bugs sem `problema_canonico` (de 314); `descoberta_feature` em 236 das 253 dúvidas (93%) e em nenhum bug; 13 tickets de infra trouxeram texto reservado a bug, gap e usabilidade.

### 7.4 Domínio e `is_atendimento` simulados [medido]

- O mapa categoria → domínio (derivado da cópia do Erick) cobre 99,0% das 1.349 categorias-ticket; 14 ficam sem domínio e 10 vêm compostas com `|`.
- `is_atendimento = true` em 1.215/1.215 pela regra do dev (não separa nada). O proxy por categoria marca 87 tickets; a natureza operacional ou ruído da B marca 123; os dois coincidem em 65.

### 7.5 Sense 2.0: o que se sabe

- A ponte confere: 99 N2/N3 do Intercom nos tickets contra 102 do censo do agente.
- O agente não grava a natureza nem o ticket por sinal, então não há como medir acerto por ticket.
- O doc registra que dois classificadores do Intercom concordam em 14% na categoria (72 pares de uma hora, 27/08).

## 8. Pontos positivos da troca por A + B

1. **Cobertura por ticket.** 1.215 tickets estruturados no dia, inclusive 391 que o agente não vê (66 N2/N3, 40% do total de N2/N3).
2. **Persistência.** Natureza, problema canônico e domínio ficam por ticket no BigQuery. O agente guarda só contagens por sinal no Notion.
3. **Sinal escondido no N1, a confirmar.** 229 dos 314 tickets que a B marca como bug (73%) estão como Dúvida (N1). O censo do agente é por N2/N3.
4. **Separação do que não é produto.** Comercial, operacional e ruído somam 366 tickets (30% do dia); 34 dos 165 N2/N3 (21%) são comerciais.
5. **Custo incremental baixo.** Cerca de US$ 0,54 por dia e US$ 11 por mês; +14% de tokens de entrada.
6. **Tempo de execução.** O job informado foi de 2,1 s (se for o da B).
7. **Compatibilidade.** A chamada A não muda; as colunas atuais seguem como estão.
8. **Qualidade técnica da saída.** JSON 100% válido, respostas determinísticas e status por chamada (o Sense 2.0 mascara falha de API com um valor padrão).
9. **Descoberta de funcionalidade.** 93% das dúvidas trazem a funcionalidade que o cliente buscava.
10. **Menos dependência de amostragem.** Sai o censo com sorteio e os shards instáveis, que o doc cita como fragilidade do agente.

## 9. Pontos de atenção na troca

1. **Assertividade não validada.** A natureza da B não tem rótulo humano. No teste de 33 tickets ela marcou como bug casos em que o produto funciona como desenhado; os 229 bugs do N1 precisam de revisão por amostra.
2. **A não reproduz o Sense 2.0 por inteiro.** 12% a 15% de diferença sem causa conhecida (possível efeito do endpoint do dev).
3. **Populações diferentes.** O agente lê conversas do Intercom (2.728); A + B leem tickets do Zendesk (1.215). A interseção é de 824 tickets (30% das conversas). Das 963 conversas que viraram ticket, 139 (14%) não estão na `dim_voc` no período de 1 a 27/10, e a causa não foi verificada.
4. **Não substitui o resto do agente.** Conversas retidas pelo bot (61% do universo do dia), taxa de escala e resolução, tendência, score e leitura continuam dependendo dele.
5. **O texto do problema não agrupa por si só.** 507 textos distintos em 530 tickets de bug, gap e usabilidade (96%), contra 130 sinais no agente. A camada de agrupamento por embeddings tem custo e tempo ainda não modelados.
6. **198 tickets sem transcrição (16%).** A natureza deles vem só de metadados.
7. **Colunas novas.** O mapa de domínio vem da cópia do Erick, cuja regra de derivação não conheço, e é atribuído por categoria, não por item. A regra do dev para `is_atendimento` não discrimina.
8. **Mais chamadas.** +80% de chamadas no dia (2.738 contra 1.523). Em produção é preciso status por chamada e nova tentativa; o incremental atual (`NOT EXISTS`, sem retry) grava a falha e não reprocessa.
9. **Duas taxonomias convivendo.** Tipo de incidente e natureza; o mapeamento entre elas e a data de corte seguem pendentes no ADR.
10. **Base curta.** Um único dia (segunda-feira), uma única medição de tempo e custos estimados por caracteres.

## 10. Recomendação

1. Manter a chamada A como está e acrescentar a B em paralelo (sombra), sem alterar a `dim_voc_full_category`.
2. Montar um conjunto rotulado por especialistas de Suporte (50 a 100 tickets, incluindo bugs em N1 e tickets sem transcrição) antes de qualquer troca no agente.
3. Gravar `usageMetadata` (tokens reais) e a duração de cada statement, para trocar as estimativas por medições.
4. Avaliar o agrupamento por embeddings do problema canônico e incluir o custo no comparativo.
5. Confirmar a causa dos 12% a 15% de diferença rodando a chamada A no endpoint de produção.

## 11. Limites desta análise

- Eu não tenho acesso ao projeto dev; os números do dia vêm de resultados colados por você.
- O job de 2,125 s foi informado sem identificar o comando; assumi que é o da chamada B.
- Os tokens e os custos são estimados; o custo do agente vem do próprio log do agente.
- Os 24 logs do agente incluem dias com mais de uma execução (WARNING e repetições).
- Sem acerto medido contra rótulo humano, tudo que se diz sobre "qualidade" é concordância ou coerência.

## 12. Arquivos

- SQL: `teste_prompt_suporte_amostra_comparativo_v2.sql` (teste de 33 tickets) e `simulacao_dia_suporte_2026-10-19.sql` (dia completo)
- Dados: `resultados-teste-prompt-suporte/` (`00` a `05`)
- Documentos: `resultados-teste-prompt-suporte-gemini.md`, `simulacao-dia-2026-10-19-sense2-vs-ab.md`, `resumo-executivo-teste-prompt-suporte-gemini.md`
