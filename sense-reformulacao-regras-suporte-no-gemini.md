# Sense - reformulação: regras do agente de Suporte na `dim_voc_full_category`

Registro consolidado da conversa de 27/10/2026 (não é transcrição literal). Reúne o que foi analisado, medido e decidido, para alimentar a documentação do To-Be.

## 1. Pergunta

1. Aprofundar a possibilidade de inserir, na `dim_voc_full_category`, as regras que o agente especialista de Suporte (V2) aplica.
2. Comparar a economia de processamento ao importar essas regras para o Gemini usado na tabela.
3. Mostrar um mesmo ticket em três cenários: tabela hoje, V2 produtivo e arquitetura 2.xx, depois a alternativa "regras no Gemini".
4. Rodar o prompt novo em três tickets irmãos e escolher a melhor opção entre V2, 2.xx e alternativa.

## 2. Fontes usadas

- Board do Miro `uXjVGhHxhRg=` (As-Is, To-Be, As-Is → To-Be).
- Página do Notion "Sense - reformulação" e "Taxonomia VoC — Proposta v1".
- Tabela `contaazul-ssbi.gold_strategy.dim_voc_full_category` (30 dias fechados até 21/10/2026).
- `sense-platform-master.zip`: `routines/prod/agente-especialista-suporte-v2.md` e `routines/shared/agente-especialista-suporte/seed-clusters.json`.
- `documentation-master.zip`: `arquitetura-domínios.md` (DDD).
- Preços do Gemini 3.1 Flash-Lite (agregadores, não a página oficial do Vertex): US$ 0,25/M entrada, US$ 1,50/M saída, cache a US$ 0,025/M, batch −50%.

## 3. Medições na tabela (30 dias fechados até 21/10)

| Fonte | Enviados ao LLM | Textos distintos | Contexto médio (chars) |
|---|---|---|---|
| zendesk | 24.451 | 23.601 | 3.979 (p50 3.384, p90 7.936) |
| aquisicao | 5.985 | 66 | 78 |
| nps | 1.482 | 256 | 42 |
| Keys-Off | 747 | 36 | 141 |
| reclame_aqui | 91 | 91 | 1.804 |
| ideas_portal | 38 | 38 | 484 |
| **Total** | **32.794** | **24.088** | |

- Template do prompt: **29.907 caracteres**, dos quais a taxonomia (272 categorias) ocupa 25.535 (**85%**), o cabeçalho 3.060 e REGRAS + FORMATO ~1,3 mil.
- Entrada total: ~269,7 M tokens/mês (4 caracteres por token, premissa do doc do Notion). Custo hoje: ~US$ 73/mês.
- Aquisição, NPS e Keys-Off gastam **23% dos tokens de entrada para 358 textos distintos**.
- O dedupe por hash tira 26,5% das chamadas; **90% delas são dessas três fontes**. No Zendesk o dedupe tira só 3,5%, e só 55 chamadas têm contexto menor que 150 caracteres. O "T0 de 25–35%" do board vem quase todo de fora do Suporte.

## 4. O que o V2 aplica e o que é portável ao Gemini

O prompt canônico de classificação do V2 tem 3.917 caracteres. A parte portável por item mede **2.296 caracteres (~570 tokens, 7,6% do template atual)**, praticamente igual ao rascunho de 2.270 feito antes de abrir o repositório.

| Regra do V2 | Onde vive no To-Be | Custo no prompt |
|---|---|---|
| Natureza: 8 valores, dissolução, precedência bug > infra > usabilidade > gap | Prompt | ~1,3 mil chars |
| Postura (dúvida, reclamação, sugestão, elogio) | Prompt; substitui `incident_type_gemini` | ~0,2 mil chars |
| Grão de descoberta (`descoberta_feature`) e `problema_canonico` | Prompt + colunas novas | ~0,3 mil chars |
| Turnos `user` = motivo; `admin`/`bot` = contexto | Adapter Zendesk/Intercom | ~0,2 mil chars |
| Evidência (≤15 palavras, sem PII) e curadoria | Prompt | ~0,2 mil chars |
| Dono DDD (só o time que conserta; bottom-up) | **JOIN** `categoria → dim_ddd_capability` | 0 |
| Cobertura (`use_case_ids`), `macro_theme` | JOIN | 0 |
| `quem_fala` | JOIN com persona do core | 0 |
| Validação de rótulo (`invalid_label`, `api_error`) | SQL | 0 |
| `match` contra o catálogo de clusters, reconciliação, piso de 3 casos, escala por balde | Camada semântica; **não importar** | — |

Pontos de atenção:

- O V2 classifica o `ai_issue_summary` do Intercom (uma linha, ~158 chars); o Gemini hoje lê a transcrição do Zendesk. As regras precisam de adapter de transcrição e de eval no golden set.
- O V2 usa assunto em texto livre (`problema_canonico`) para não perder o sinal fino. Importar as regras **acrescenta** esse campo e a natureza; a `category_gemini` continua como roteamento.
- Colar o catálogo de clusters no prompt custaria +US$ 18/mês só com o seed (50 clusters, ~10 mil chars). Extrapolando para os 250+ clusters citados no Notion, da ordem de US$ 90/mês.

## 5. Comparativo de processamento (Gemini, 30 dias)

| Cenário | Custo/mês | vs hoje |
|---|---|---|
| S0 Hoje (prompt único, 272 categorias) | US$ 73 | — |
| S1 Anexar as regras ao prompt único, todas as fontes | US$ 81 | +10% |
| S2 Substituir pela Taxonomia v1 (177 categorias) | US$ 74 | +1% |
| S3 Prompt por fonte + regras só no Zendesk/RA + shortlist | US$ 30 | −59% |
| S4 = S3 + dedupe + limpeza da transcrição (−40% no Zendesk) | US$ 22 | −70% |
| S5 = S4 + cache de prefixo | US$ 11 a 18 | −75% a −85% |
| Alternativa mínima (taxonomia v1 inteira + regras, só dedupe) | US$ 59 | −19% |
| Alternativa completa (shortlist por metadado) | US$ 26 a 32 | −64% a −56% |

Leitura: anexar as regras não economiza nada; a economia vem de compor o prompt por fonte, usar shortlist, deduplicar e limpar a transcrição. Por ticket do Zendesk: US$ 0,0023 hoje, US$ 0,0011 na alternativa, US$ 0,0009 na 2.xx.

### V2 em números

Primeira run de produção: ~690 mil tokens, US$ 4,55.

| Etapa | Tokens | US$/run | US$/mês | Portável ao Gemini |
|---|---|---|---|---|
| Classificação | ~353 mil | 2,33 | ~70 | Sim |
| Reconciliação (self-merge) | ~236 mil | 1,56 | ~47 | Não (vira embeddings + juiz) |
| Resto | ~100 mil | ~0,66 | ~20 | Não |

- Custo de classificação do V2: US$ 0,0036 por item (552 tokens).
- Cobrir 100% das conversas (1.340/dia): V2 só na classificação ~US$ 146/mês; Gemini com regras importadas **US$ 14 a 31** (sem cache a US$ 31, cache só no núcleo US$ 25, tudo em cache US$ 14).

## 6. Mesmo ticket em três cenários

Ticket Zendesk **6189021** (19/10/2026): boleto pago e não baixado automaticamente. A linha 1 é real; as demais aplicam as regras documentadas e são projeções.

### 6.1 Hoje na `dim_voc_full_category` (linha real)

| Campo | Valor |
|---|---|
| `source` / `id_ferramenta` | zendesk / 6189021 |
| `ticket_type`, `category`, `ticket_subcategory` (fonte) | Ajustes (N2); cobrança; prazos e taxas da cobrança conta azul |
| `reason` | prazo para compensação |
| `transcription` | 3.709 caracteres |
| `sentiment` | Raiva |
| `macro_theme` | Produto |
| `incident_type_gemini` | Incidentes |
| `incident_summary_gemini` | Pagamento de boleto de venda não baixado automaticamente, frustração com dificuldade de localizar a venda pelo atendimento automatizado |
| `category_gemini` | **Cobrança - Regua / Envio de cobrança** (parece desalinhada com o resumo) |
| `full_prompt` | 34.163 caracteres |

Os outros dois tickets irmãos (6178426, Pix de boleto não baixado; 6188174, boleto Sicoob) tiveram outro tipo de incidente cada um (Dúvida e Reclamação), e um deles caiu em outra categoria.

### 6.2 V2 produtivo (regras do MD, não execução)

O V2 não grava o ticket: conta o ticket em um cluster no Notion. Só entra se houver conversa Intercom associada e lê o `ai_issue_summary`. Como é N2, entra no censo com peso ×1 (um N1 sorteado pesaria ×3,33).

| Propriedade do cluster | Valor |
|---|---|
| `Sinal` | Boleto pago não baixado/compensado (cluster do seed) |
| `Tipo (natureza)` | bug |
| `Domínio` / `Subdomínio` | Banking & Cash › Receivable (entra Core Accounting só se a baixa for o ponto de falha) |
| `Menções` | agregado do cluster no dia, +1,0 deste ticket |
| `Tendência`, `% escala`, `% N2+` | agregados por cluster (dia útil contra dia útil) |
| `Leitura do especialista` | síntese do cluster |

O mapeamento ticket → cluster não é gravado, nem a natureza por ticket. Não há tabela BigQuery do lado do V2.

### 6.3 Alternativa: regras importadas no Gemini (projeção)

Mesma tabela física, mesmo `AI.GENERATE`, prompt por fonte, shortlist por metadado.

| Campo | Valor |
|---|---|
| `natureza` / `postura` (novos) | bug / reclamação |
| `problema_canonico` (novo) | "Pagamento de boleto de venda não baixado automaticamente" (texto livre) |
| `descoberta_feature`, `curadoria`, `evidencia` (novos) | nulo, falso, trecho de até 15 palavras |
| `category_gemini` | Boleto Registrado (ex.); uma 2ª categoria de atendimento por bot geraria uma 2ª linha |
| `capability_id`, `dominio`, `subdominio` (novos, JOIN) | Banking & Cash › Receivable |
| `status` | ok |
| `cluster_id` | não existe |
| Prompt | ~13,4 mil caracteres (era 34.163) |

### 6.4 Arquitetura 2.xx (projeção)

| Camada | Objeto | Para o ticket 6189021 |
|---|---|---|
| Core | `core_voc_interaction` + `core_voc_text_raw` | `voc_id` = hash(zendesk + 6189021), persona por JOIN, transcrição restrita |
| T0 | Triagem SQL | passa (tem insumo, hash inédito) |
| T1 | Prompt composto (núcleo cacheável + adapter + shortlist) | ~10 mil caracteres |
| Enriquecimento | `ai_voc_extraction` | natureza bug; postura reclamação; `problema_canonico` como acima; categoria Boleto Registrado (ex.); status ok |
| Enriquecimento | `bridge_voc_category` | categoria principal (+ 2ª de atendimento por bot, se houver) |
| Semântica | embedding + busca no balde (capacidade DDD + natureza) | candidatos de cluster; similaridade alta atribui automático, zona cinza vai ao juiz |
| Semântica | `bridge_voc_cluster` | ticket → "Boleto pago não baixado/compensado", com método e similaridade |
| Sinal | `fct_signal_monthly` | conta 1, exato |
| Compatibilidade | `dim_voc_full_category` (VIEW) | mesma linha de hoje, derivada das novas tabelas |

## 7. Alternativa × 2.xx para o mesmo ticket

| Dimensão | Alternativa | 2.xx |
|---|---|---|
| Onde a linha vive | `dim_voc_full_category` física | Core + `ai_*` + bridges; a tabela vira VIEW |
| Grão | Ticket Zendesk; conversas só de bot ficam de fora | Conversa Intercom com tickets filhos |
| Multi-categoria | Uma linha por categoria; `COUNT(*)` superconta | Bridge com `is_primary` |
| Identidade do problema | Texto livre por ticket | `cluster_id` vitalício |
| Contar o problema | Por categoria + natureza (balde misto) | Exato por cluster |
| Tendência, Score, Leitura | Seguem no V2 | `fct_signal_monthly`, score em SQL, síntese em batch |
| V2 | Segue (~US$ 137/mês) ou lê as colunas novas e dispensa ~US$ 70 | Substituído (V3 em shadow) |
| Reprocesso | Acoplado ao incremental do Dataform | `ai_*` append-only por `input_hash` |
| Cache de prefixo | `AI.GENERATE` (sem cache segundo o Notion, não verificado) | Job no Vertex permite cache |
| Esforço | Fases 1 e 2 | Fases 2 a 4 |

Risco principal da alternativa: cada ticket é uma chamada independente, então o mesmo problema pode sair com textos diferentes no `problema_canonico` (risco raciocinado, não medido).

## 8. Teste real: executado em 28/10/2026

O teste foi executado em 4 rodadas, com acesso a `contaazul-datalake-dev` pelo `us.vertex_connection`. Resultados completos, método e limites em `resultados-teste-prompt-suporte-gemini.md`; dados brutos em `resultados-teste-prompt-suporte/`.

Rodada 1 (3 tickets irmãos, 3 repetições, gemini-2.5-flash-lite): repetições idênticas em todos os campos. As categorias e o tipo divergiram do gravado, mas o prompt era outro (lista filtrada, uma categoria só, natureza + postura).

Rodadas 2 a 4 (33 tickets: 3 originais, 12 do tema boleto/Pix, 18 estratificados por tipo):

- **Replay do prompt de produção** com gemini-3.1 sem `output_schema` reproduz o gravado em 85% a 88% (macrotema 88%, tipo, sentimento e categorias exatas 85%). As duas repetições são idênticas nos 33 tickets. Com gemini-2.5 a concordância era de 39% a 58%.
- **`output_schema` com gemini-3.1** gerou 17 falhas de parse em 66 chamadas e outras 14 incompletas. Sem `output_schema` (como na produção), 99/99 válidas.
- **Campos novos dentro do prompt de produção** empurraram tipo e sentimento para Incidentes e Insatisfação. Em chamada separada (B) a natureza ficou mais coerente: 11 bugs, 9 dúvidas, 5 comerciais, 3 gaps.
- **`problema_canonico`:** 15 tickets com texto e 15 textos distintos. Os do tema "pagamento não baixado" ficam próximos, mas nenhum se repete, então agrupar exige embeddings ou normalização.
- **Limite:** concordância com o gravado não é acerto, e não há rótulo humano na amostra. A diferença de 12% a 15% para o gravado não vem do prompt (é o mesmo) nem de nondeterminismo.

Decisão provisória: chamada A com o prompt de produção para as colunas legadas e chamada B separada para os campos novos, sem `output_schema`. Query final: `teste_prompt_suporte_amostra_comparativo_v2.sql`.

A conclusão da seção 9 ("etapa curta antes da camada de embeddings") se mantém.

## 9. Comparativo final: V2 × 2.xx × alternativa

| Critério | V2 produtivo hoje | Arquitetura 2.xx | Alternativa (regras no Gemini) |
|---|---|---|---|
| Cobertura de Suporte | Censo N2/N3 + sentimento negativo + 30% do resto | 100%, incluindo conversas só de bot | 100% dos tickets; bot-only fora |
| O que persiste | Cluster no Notion; ticket não guardado | Ticket, extração e vínculo ticket→cluster | Ticket, sem vínculo com cluster |
| Identidade do problema | Cluster nomeado pelo agente | `cluster_id` vitalício | Texto livre por ticket |
| Contagem | Estimada (×3,33 na amostra) | Exata por cluster | Por categoria + natureza |
| Tendência, Score, Leitura | Sim | Sim | Não |
| Custo de LLM/mês | ~US$ 137 (US$ 70 de classificação) | US$ 11 a 22 de extração + camada semântica (Notion: US$ 30–40 no Suporte) | US$ 26 a 32 |
| Esforço | Em produção | Fases 2 a 4 | Fases 1 e 2 |
| Risco principal | Teto de contexto; run fecha com ⚠️ | Calibrar limiares de embedding | Vocabulário instável do texto livre |

### Recomendação

- **2.xx é a melhor como destino**: única com cluster, contagem exata e rastreabilidade. A escolha é por capacidade, não por custo.
- **Alternativa é o melhor primeiro passo, não concorrente**: as colunas que cria viram o `ai_voc_extraction` e o prompt por fonte vira o núcleo mais adapter.
- **V2 continua até a V3 provar paridade**: meta do plano de ≥80% dos 20 maiores clusters do V2 aparecendo na V3 na mesma janela.
- O que o teste real decidiu (seção 8): as repetições saem idênticas, mas os textos de `problema_canonico` entre tickets diferentes do mesmo problema não se repetem (15 textos em 15 tickets). A alternativa serve como etapa curta antes da camada de embeddings.

## 10. Premissas e o que não foi verificado

- 4 caracteres por token (premissa do doc do Notion); em 3,5 o custo de hoje vai de ~US$ 73 para ~US$ 83, sem mudar os percentuais.
- Tokens de saída: 120 por item hoje e 180 com o schema novo (premissa minha).
- Preço de cache e batch do Gemini vêm de agregadores; "AI.GENERATE sem cache de contexto" vem da linha de risco do Notion, não confirmada.
- Tamanho da shortlist por metadado (8 a 12 mil caracteres) é premissa minha; a shortlist por embedding (~5 mil) vem da faixa do Notion.
- Natureza, postura, categoria "Boleto Registrado" e domínio nas tabelas 6.2 a 6.4 são projeções; dependem da lista final de 177 categorias e do eval no golden set.
- Mapeamento natureza + postura → `incident_type_gemini` na view de compatibilidade ainda precisa ser definido no ADR, com data de corte da quebra de série.
- Custo da camada semântica da 2.xx (embeddings, juiz, síntese) não foi modelado.

## 11. Próximos passos sugeridos

1. ~~Rodar o teste real~~ Feito em 28/10/2026 (seção 8). Pendente: golden set rotulado para medir acerto e `problema_canonico` por similaridade (embeddings).
2. Montar a seção do Notion com o bloco de regras adaptado para transcrição, a tabela de portabilidade e o comparativo.
3. Definir no ADR o mapeamento natureza + postura → `incident_type_gemini` e a data de corte.
4. Rodar o eval no golden set com o prompt composto antes de qualquer troca em produção.
