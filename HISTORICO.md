# Histórico, decisões e ideias

Resumo organizado do trabalho feito nas conversas com o Claude sobre a reformulação do Sense, até 29/10/2026. Os detalhes e os dados estão nos arquivos citados em cada seção. Onde um número é estimativa ou leitura minha (do Claude), está marcado.

## 1. Objetivo

Entender como o Sense 2.0 funciona hoje, onde estão o custo e a dependência do Claude, e se um **LLM auxiliar barato (Gemini 3.1 flash-lite)** na camada de dados, antes dos agentes, pode assumir o trabalho por item (extrair campos, casar com um catálogo) e deixar para o Claude o julgamento (nomear o novo, consolidar, pontuar, escrever a Leitura).

## 2. Linha do tempo

| Quando | O que aconteceu | Onde está |
|---|---|---|
| Antes de 27/10 | O Sense 1.0 ficou parado desde 17/08/2026. O NPS lê só 3 de 21 colunas da VoC. Proposta de VoC genérica mais VoC especialista por área. | `propose-voc-generica-e-especialistas.md`, `sense-reformulacao-contexto.md` |
| 27/10 | Brainstorm com Philipi, André e Erick: amostra de 30%, redundância entre Intercom e VoC, logs do Notion para o data lake. | `investigacao-dev-dim-voc-full-category.md`, `arquitetura-tabelas-voc-dataform.md` |
| 27 a 28/10 | Investigação da `dim_voc_full_category` no dev (cópia do Erick, com `domain`, `subdomain` e `is_atendimento`). O acesso ao dev não existe pelo MCP; os scripts são rodados no console. | `investigacao-dev-dim-voc-full-category.md` |
| 28/10 | **Teste A + B** em 33 tickets, 4 rodadas (Gemini 2.5 e 3.1). A = prompt de produção sem alteração; B = campos novos (natureza, problema canônico, descoberta de feature). | `resultados-teste-prompt-suporte-gemini.md`, `resultados-teste-prompt-suporte/` |
| 28/10 | **Simulação de um dia completo** (19/10) comparando o agente de Suporte do Sense 2.0 com A + B sobre a população inteira. | `simulacao-dia-2026-10-19-sense2-vs-ab.md`, `comparativo-ab-vs-sense2-0.md` |
| 29/10 | Pesquisa em documentação: por que o Intercom é a fonte primária e por que conversas que não viraram ticket entram no agente. | Resposta no histórico da conversa; resumo na seção 3.4 |
| 29/10 | Acesso ao repositório `sense-platform`, leitura do prompt de prod do Suporte V2 e **justificativa de design**. | `justificativa-design-agente-suporte-v2.md` |
| 29/10 | Mapa dos outros agentes e **plano de testes de LLM auxiliar** (AUX-S, AUX-N, AUX-P, AUX-O, AUX-X). Desenho no Miro. | `plano-testes-llm-auxiliar-gemini-outros-agentes.md`, Miro |
| 29/10 | Resultados dos testes AUX, correção do parse do Suporte, script v2 do Portal, linha de base e cobertura de 100%. | `resultados-teste-aux-gemini.md` |
| 29/10 | Custo e tempo reais da DB de Logs; quadro "Resumo: as is, to be e tbd" no Miro. | Miro, `README.md` |

## 3. Achados e decisões

### 3.1 Teste A + B (28/10)

- **Chamada A** (prompt de produção, ~30 mil caracteres, ~273 categorias) reproduz a classificação gravada em 85 a 88% dos 33 tickets (macrotema 88%, tipo e sentimento 85%). As duas repetições saem idênticas nos 33. Os 12 a 15% restantes não vêm do prompt nem da variação entre execuções; causa não confirmada (pode ser o endpoint de dev contra o de prod).
- **Chamada B** (natureza, problema canônico, descoberta): saída válida em 99 de 99 chamadas **sem `output_schema`**. Com `output_schema` no Gemini 3.1, 17 de 66 chamadas falharam.
- O **problema canônico não se repete** entre tickets (96% distintos): contar problemas exige agrupar por similaridade (embeddings), não por igualdade de texto.
- Custo extra de A + B: ~+11% no dia (US$ 5,42 contra US$ 4,88) e ~+8,6% no mês (estimativa de 29/10, a 4 caracteres por token e preços de agregadores).

### 3.2 Simulação do dia 19/10

- Universo do Intercom: 2.728 conversas (idêntico ao universo da V2). 1.215 tickets do Zendesk na dim. 824 desses tickets vieram do Intercom e 391 não. 1.904 conversas (70%, a maioria retida pelo bot) não têm ticket.
- A V2 lê ~705 conversas (707 na minha reprodução da seleção). Os dois números (705 e 1.215) medem coisas diferentes: conversas do Intercom selecionadas contra tickets do Zendesk na `dim_voc`.
- Ponte entre Intercom e Zendesk: `silver_serve.zendesk_concatened_messages` (`ticket_id` e `intercom_conversation_id`).

### 3.3 Design do Suporte V2 (justificativa)

- A V2 existe porque o volume cresceu 11 vezes em 5 meses (4,3 mil conversas em fevereiro, 49 mil em julho) e o censo em muitos shards era frágil e O(N).
- Regras centrais: seleção só por metadado em SQL; clusterização do `ai_issue_summary` por LLM (nunca regex); contagem escalada por balde (censo x1, amostra x3,33); piso de 3 conversas cruas depois de consolidar; barreira de reconciliação que falha alto; zero tabela BigQuery do nosso lado; emite sinal e nunca cria OP.
- Quase toda regra dura é cicatriz de um incidente (runs de 05/08, 04/09, 05/09, 11 a 14/09, 10 e 14 a 17/10).
- Premissa mais importante: **o custo é o raciocínio do Claude**, não o tamanho do texto. Na 1ª run de prod, ~589 mil dos ~690 mil tokens vieram de duas chamadas de Agent.

### 3.4 Por que o Intercom é a fonte primária (documentação)

- A classificação pronta do Intercom (`subjects`, `subcategory`) é vazia em 30 a 49% e grossa; a transcrição classificada por LLM é a fonte.
- O estado de resolução do bot (escalou ou resolveu no chat) só existe no Intercom e alimenta o fator de deflection do Score.
- Conversas só do bot entram para o denominador do deflection e porque a insatisfação do cliente aparece também nelas (no relatório de 14/09, 9 de 11 conversas com CSAT negativo nunca chegaram a ticket).
- O Zendesk entra como enriquecimento (N2/N3, tempo, perfil).

### 3.5 Custo real do Sense (DB de Logs, estimativa por tokens)

| Mês | Total | Onboarding | Suporte V2 | Cross |
|---|---|---|---|---|
| Ago/26 (parcial, go-live em 22/08) | US$ 227 | US$ 119 | US$ 72 | US$ 35 |
| Set/26 | US$ 359 | US$ 222 | US$ 122 | US$ 9 |
| Out/26 (até 29/10) | US$ 367 | US$ 238 | US$ 69 | US$ 56 |

- Suporte V2, últimos 30 dias: 29 runs, ~US$ 2,5 e ~380 mil tokens por run, duração média ~22 min (só 8 runs têm tempo registrado), 10 de 29 com aviso.
- Onboarding: ~US$ 9 por run, ~1,4M tokens, ~31 min; lê as transcrições inteiras por regra (I5). É o maior custo.
- Cross: 1 run em 30 dias, ~8,5M tokens, ~US$ 56.

### 3.6 Testes AUX (Gemini antes dos agentes), 29/10

| Agente | Resultado | Números |
|---|---|---|
| pNPS | Melhor candidato | JSON 99,7%; Spearman 0,89 e Pearson 0,94 contra o agente; 6 de 9 N2 fora de ±20%; ~US$ 0,11 por rodada |
| Suporte | Não substitui o casamento do Claude ainda | JSON 100% (depois de corrigir o parse); Spearman 0,60 contra a V2; teto de amostragem 0,86; casamento forçado (96% casadas com catálogo de 53% dos sinais) |
| Portal | Inconclusivo | Cluster certo ~35%; a "verdade" (backfill) é grossa; 930 de 10.160 itens com tema inconsistente entre `cluster_map` e `cluster_meta` |

- Causa dos JSON inválidos do Suporte: quando o resumo tem várias perguntas, o Gemini devolve um array com um objeto por pergunta, e o parse guloso quebrava (110 e 48 respostas, os mesmos números dos inválidos).
- **Teto de amostragem:** o Gemini em 30% contra o Gemini em 100% (mesmo classificador) dá Spearman 0,86, top-10 de 9 e erro de 26%. O Gemini contra a V2 do mesmo dia dá 0,60; a V2 contra o Gemini em 100% dá 0,53. O gap vem do classificador, não da amostragem.
- **Correção registrada:** a "linha de base" da V2 entre dias (Spearman 0,48) mede outra coisa (volume e amostras diferentes por dia) e não deve ser critério de aceite.
- Nenhum resultado prova acerto: falta rótulo de especialista.

## 4. Ideias e hipóteses em jogo

1. **A + B:** um prompt generalista (o de produção, intacto) mais um prompt especialista em chamada separada, por ticket.
2. **LLM auxiliar na camada de dados** (Dataform), antes do agente, gravando uma tabela por item. Dentro do agente não cabe: um agente tem um modelo só.
3. **Expandir o Suporte para 100%** com o Gemini (~US$ 1,70 por dia no casamento): contagem exata e cauda rara visível. A V2 superestima ~7% nos 100 sinais testados.
4. **Gemini propõe, Claude valida:** o Gemini casa; o Claude só trata os "sem match" (~3%), as divergências e a Leitura.
5. **Execução em paralelo (sombra)** por 2 a 3 semanas, sem escrever em nada (~US$ 50 por mês), com as divergências como fila de rótulo.
6. **pNPS:** a tabela de rótulos por comentário é a "DB de Comentários" que o prompt do agente trata como evolução futura.
7. **Onboarding:** só como leitor paralelo, porque a regra I5 proíbe substituir a leitura.
8. **Embeddings** (V3) para o problema canônico e para reduzir catálogos grandes.
9. **Colunas na `dim_voc`:** `domain`, `subdomain`, `is_atendimento`, `source = 'intercom'`, `ticket_level`, estado de resolução.

## 5. Pendências

- Rótulo de especialistas: R8 (Suporte), R7 (pNPS) e ~50 discordâncias do Portal.
- V2 em 100% (o Claude lendo os 1.961 resumos): não medido; custo da ordem de 3 vezes uma run.
- Redução real de custo e tempo do Claude com entrada reduzida (fase 2).
- Autoconsistência (`n_reps = 2`) nunca medida.
- Onboarding: decisão do dono sobre um segundo leitor barato (regra I5) e export de 30 transcrições.
- Portal: revisar os 930 itens com tema inconsistente e os clusters com 20 ou mais ideias (43% dos itens).
- Origem e corrupção do `ai_issue_summary` no Intercom (o Dataform só extrai o atributo).
- Trocar a taxa de amostra de 30% para 100% corta a série diária (política de "rebase"); isso afeta a tendência que o Cross lê.
- Confirmar qual job tem o tempo de 2,125 s citado na simulação do dia 19/10 (suposto ser a chamada B).

## 6. Como retomar

- Docs de contexto: `README.md`, este arquivo e `LINKS.md`.
- Resultados mais recentes: `resultados-teste-aux-gemini.md` (seções 9 a 11).
- Board no Miro: ver `LINKS.md`.
- Código dos agentes: repositório `ContaAzul/sense-platform` (pasta `routines/prod/`).
