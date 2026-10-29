# Sense — Reformulação da arquitetura · Contexto da conversa

> Conversa de 21/10/2026 no Project "sense - reformulação" (claude.ai).
> Este arquivo resume o que foi pedido, as fontes consultadas, os fatos medidos, as decisões propostas, os artefatos produzidos e as pendências. Serve como ponto de partida para retomar o trabalho em outra sessão.
> A versão completa e formatada da proposta está no Notion (link na seção 3).

---

## 1. Pedido original

O pedido foi analisar a arquitetura atual do Sense e da VoC com o olhar de arquiteto de plataforma, engenheiro de dados e engenheiro de IA/FinOps, e propor uma reformulação que permita processar **100% da população**, em vez de amostra.

Três perguntas centrais:

1. **Modelagem da `dim_voc_full_category`.** É melhor manter uma tabela monolítica ou adotar uma tabela Core que cascateia para Data Marts por canal? Considerar performance, custo de storage/query e governança.
2. **Arquitetura de agentes.** A topologia atual é 1 orquestrador + N especialistas. Dá para consolidar num Single Agent com roteamento via prompt dinâmico/RAG, ou o caminho é um pipeline em batch (ex.: PySpark + chamadas assíncronas)?
3. **FinOps.** Como viabilizar 100% da população se o As-Is já é caro em amostragem? Considerar troca de modelos, modelos menores para triagem, batch e caching.

Formato pedido: Markdown com 5 seções, na ordem:

1. As-Is e gargalos
2. Modelagem
3. Agentes
4. FinOps
5. To-Be

---

## 2. Fontes consultadas

| Fonte | Onde | Observação |
|---|---|---|
| Prompt do Especialista de Suporte V2 (PROD) | upload `agente-especialista-suporte-v2.md` | ~440 linhas, a maior parte guarda-corpos |
| Planilha "Definição de Categorias do VoC" | https://docs.google.com/spreadsheets/d/17Ftv8f_h_VZ_MZM2En0Pq_4oHLemP480wJ2kGYbXW9w | Abas MACROTEMA, TIPO DE INCIDENTE, SENTIMENTO, SUBCATEGORIA, CAPRO, CAMAIS, Transversal, elemento por produto, SUBTESTE |
| Sense — Central (página legada) | https://app.notion.com/p/3a34a554a42f8118ae36fe0582381266 | Visão geral do Sense 1.0/2.0 |
| Categorização VoC por LLM — como funciona | https://app.notion.com/p/3cd4a554a42f816d969ee2018ad2182f | Como a `dim_voc_full_category` funciona |
| Taxonomia VoC — Proposta v1 | https://app.notion.com/p/3ca4a554a42f81cea93dfd3ed457a054 | 177 categorias, 4 eixos, ids estáveis |
| Manual de seleção de modelo por agente Sense | https://app.notion.com/p/3aa4a554a42f81eda23cf4ac16a9d635 | Loop empírico de custo × qualidade |
| Definição Dataform | `tables/contaazul-datalake-prod/gold_strategy/dim_voc_full_category`, via Blue `search_dataform` | |
| BigQuery (read-only, últimos 30 dias) | projeto `contaazul-ssbi` | Queries no apêndice |
| Board de arquitetura (Miro) | https://miro.com/app/board/uXjVGhHxhRg=/ | O As-Is fica no "Frame 1" |
| GitHub `ContaAzul/documentation` e `ContaAzul/sense-platform` | — | **Não acessados**: repositórios privados (ver seção 8) |

---

## 3. Artefatos produzidos

- **Página no Notion "Sense - reformulação"**: https://app.notion.com/p/3ff4a554a42f80aa8dd3d02bb2ba9ced
  - Conteúdo:
    - resumo executivo;
    - seções 1 a 5 da análise;
    - plano de execução;
    - métricas de sucesso;
    - decisões em aberto;
    - riscos;
    - apêndice de evidências.
  - Diagramas As-Is e To-Be em Mermaid.
  - Links para os frames do Miro no callout do topo.
- **Miro, no board de arquitetura, à direita do As-Is:**
  - Frame "Sense 2.x · Arquitetura To-Be" (id `3458764687960452512`): https://miro.com/app/board/uXjVGhHxhRg=/?moveToWidget=3458764687960452512
    - Contém título, legenda por tipo de executor e um widget Mermaid editável (id `3458764687960452550`).
    - O frame foi dimensionado por estimativa (7600 × 2600), porque o widget se redimensiona sozinho. Ainda falta conferir se o diagrama coube.
  - Frame "Do As-Is ao To-Be" (id `3458764687960452513`): https://miro.com/app/board/uXjVGhHxhRg=/?moveToWidget=3458764687960452513
    - Contém as 4 mudanças principais e as 6 fases do plano.
- **Este arquivo**: `sense-reformulacao-contexto.md`.

---

## 4. Fatos e medições-chave

### 4.1 Esteira A — VoC populacional (`gold_strategy.dim_voc_full_category`)

- **Execução:** modelo Dataform incremental que chama `AI.GENERATE` com `gemini-3.1-flash-lite` dentro do SQL.
  - Parâmetros: `thinking_budget` 0, `temperature` 0, label `ca_initiative = voc_v2`.
  - Fontes: 7 (Zendesk, NPS, aquisição, Keys-Off, portal de ideias, Reclame Aqui, portal de vendas).
  - Taxonomia: 272 subcategorias.
- **Origem do prompt:** o template vem da última linha (por `dt_atualizacao`) de `bronze_tool_ext_google_sheets.voc_prompt`, uma tabela externa sobre Google Sheet.
  - O `full_prompt` é gravado **em cada linha** e é a única linhagem do prompt usado.
- **Incremental sem retry:** o filtro é `NOT EXISTS` por `(source, id_ferramenta)`, então uma linha gravada nunca é reprocessada. Um full refresh reclassifica tudo desde 2025-01-01.
- **Default silencioso:** `COALESCE(cc.cat, 'Não é possível determinar') AS category_gemini`, e o mesmo valor é injetado em `canonical_cats`.
  - Os ~180 mil "Não é possível determinar" vêm do pipeline, não do LLM. Isso responde a ressalva #1 da página de Categorização.
  - Erro de API, JSON inválido e "indeterminado" ficam indistinguíveis.
- **Grão misto:** a categoria explode em linhas (1 linha = interação × categoria), enquanto macrotema e tipo pegam só o 1º valor.
- **Volume:** ~924 mil linhas e 607 partições diárias (Notion, set/2026). Não há assertions declaradas no Dataform.
- **Consumidores conhecidos:** explores Looker `nps_blended` e `nps_detractor_themes_30d`.

**Medição de 30 dias:**

| Fonte | Itens | Linhas | Textos distintos enviados | Média de chars do prompt |
|---|---|---|---|---|
| zendesk | 24.424 | 27.734 | 23.593 | 33.882 |
| aquisicao | 6.050 | 6.059 | 67 | 29.991 |
| nps | 1.381 | 1.436 | 247 | 29.956 |
| Keys-Off | 749 | 758 | 37 | 30.055 |
| reclame_aqui | 92 | 177 | 92 | 31.729 |
| ideas_portal | 40 | 52 | 40 | 30.385 |

**O que a medição mostra:**

- Total de ~32,7 mil itens em 30 dias (~1,1 mil/dia), todos enviados ao LLM.
- ~1,08 bilhão de caracteres enviados.
- O template fixo tem **29.908 caracteres**, o que representa **91% do input**.
- **26% das chamadas repetem input idêntico.**
- A razão é de 1,11 linha por item no geral e 1,9 no Reclame Aqui.
- O payload médio de NPS é ~48 caracteres: a maior parte é só a classificação, sem comentário.
- Custo estimado: ~US$ 70–80/mês, ou ≈ US$ 0,002/item (premissa de ~4 caracteres por token).
- Uma consulta de 30 dias tocando as colunas de texto processou 1,34 GB.

### 4.2 Esteira B — Sense 2.0

- **Topologia:** 4 especialistas (Suporte, pNPS, Onboarding, Portal) mais o Cross. Todos rodam como sessões agênticas standalone.
  - O orquestrador da 1.0 foi removido. O Cross mensal faz o papel de hub.
  - O estado (DBs de Sinais, catálogo, Oportunidades) fica no Notion.
- **Suporte V2:**
  - Censo de N2/N3 e negativos, mais 30% do restante por `FARM_FINGERPRINT`.
  - Lê `ai_issue_summary` e clusteriza em contexto.
- **Custo da 1ª run prod:** ~690k tokens (US$ 4,55).
  - ~353k tokens para classificar ~640 resumos.
  - ~236k tokens para reconciliar.
  - Isso dá ~1,08k tokens por item, ≈ US$ 0,007/item, ≈ US$ 135/mês.
- **Limitações:**
  - O Modo B (merge cross-run) está bloqueado porque não há `cluster_id` imutável nem ledger.
  - O mapa sinal→cid não é persistido.
  - O Notion não tem compare-and-set.
  - O censo exigiu 15–18 shards, que se mostraram instáveis.
- **Classificadores concorrentes:** ainda rodam `silver_serve.intercom_llm_classification` e o próprio `ai_issue_summary` sobre as mesmas conversas. Num recorte medido, a concordância entre dois deles foi de 14%.

### 4.3 Intercom (base do Suporte), últimos 30 dias

- ~1.760 conversas por dia.
- 76% têm `ai_issue_summary`, o que dá ~1.340 itens classificáveis por dia.
- O resumo médio tem 158 caracteres, e 97% dos resumos são distintos.
- **Projeção:** o desenho agêntico atual a 100% custaria ≥ US$ 290/mês só para Suporte, além da fragilidade dos shards.

### 4.4 Defeitos observados na planilha de categorias

- Na aba SUBTESTE, a linha do Boletão está com o nome em branco.
- "Serviço de Backup" aparece duplicado.
- "Emissão NF-e - Melhorias Informações complementares (ex" está truncado no ":". Esse é o mesmo delimitador usado pelo parser `^([^:]+):` no Dataform.
- A aba "elemento por produto" já separa as categorias em `capro`, `camais` e `transversal`. Essa separação é útil para fazer shortlist da taxonomia no prompt.

---

## 5. Diagnóstico

1. **LLM usado como motor de ETL.** O prompt V2 reimplementa em prosa o que a plataforma de dados faz de forma determinística: amostragem, fan-out, barreiras, ledger e idempotência.
2. **O custo está no raciocínio, não no input.** São ~27 tokens de raciocínio por token de sinal.
3. **O teto de contexto força amostragem.** Isso leva a contagens estimadas (×3,33), cauda perdida, Score só ordinal e Tendência comparável apenas na mesma taxa.
4. **Notion usado como state store.**
5. **Classificação redundante** sobre os mesmos dados.
6. **Inferência acoplada à materialização** na Esteira A.
7. **Default silencioso** ("Não é possível determinar" vindo do pipeline).
8. **Prompt sem governança** (planilha sem review e sem eval).
9. **Desperdício de input:** template repetido em toda chamada e chamadas duplicadas.

**Conclusão-chave:** a esteira barata (A) já cobre 100% da população. Viabilizar 100% no Sense significa **mover o map (entendimento por item) para a esteira populacional**, e não otimizar o agente.

---

## 6. Decisões propostas

### 6.1 Modelagem: Core + Marts

O BigQuery é colunar, então a largura da tabela não é o problema. Os problemas reais são o grão misto, o acoplamento e a governança. A proposta é: core estreito no grão de interação, mais enriquecimento IA versionado e append-only, mais marts por canal (OBT na borda).

| Camada | Objeto | Grão |
|---|---|---|
| Staging | `stg_voc_<fonte>` | registro da fonte (contrato comum, PII redigida, content_hash) |
| Core | `core_voc_interaction` | 1 interação (`voc_id = hash(source, source_id)`) |
| Core restrito | `core_voc_text_raw` | 1 interação (texto integral, policy tag) |
| Enriquecimento | `ai_voc_extraction` | voc_id × extractor_version (com status ok/invalid_label/api_error/skipped) |
| Enriquecimento | `bridge_voc_category` | voc_id × category_id (is_primary) |
| Enriquecimento | `ai_voc_embedding` | voc_id × modelo |
| Referência | `dim_voc_category` (SCD2) | categoria × vigência; o prompt é uma projeção desta tabela |
| Referência | `dim_prompt_version` | versão (substitui o `full_prompt` por linha) |
| Semântico | `dim_voc_cluster` | cluster_id imutável |
| Semântico | `bridge_voc_cluster` | voc_id × cluster_id (o mapa sinal→cid) |
| Semântico | `log_cluster_merge` | evento (ledger que destrava o Modo B) |
| Agregado | `fct_voc_cluster_daily` | cluster × dia × fonte (contagem exata) |
| Marts | `mart_voc_suporte` / `_nps` / `_onboarding` / `_portal` / `_cross` | por consumo |
| Compatibilidade | `dim_voc_full_category` como VIEW | mantém os explores de NPS durante a migração |

**Decisões físicas:**

- O core é particionado por data e clusterizado por source e produto, com `require_partition_filter`.
- As tabelas `ai_*` são append-only.
- Agregados diários usam materialized views.
- Nenhum mart carrega texto bruto.

**Grão de Suporte:** a unidade é a conversa do Intercom, com os tickets do Zendesk como filhos. A deduplicação acontece uma única vez no staging.

### 6.2 Agentes: um extrator único, várias lentes

- O trabalho atual dos especialistas se divide em quatro tipos:
  1. Seleção e métricas → SQL.
  2. Entendimento por item (map) → extração em batch.
  3. Agrupamento (reduce) → embeddings + LLM só nas bordas.
  4. Síntese e priorização → LLM ou agente sobre agregados.
- **Single Agent populacional:** não. Esbarra em teto de contexto, não determinismo e custo ∝ raciocínio.
- **Routing Agent:** não. O roteamento deve ser por metadado, em SQL (fonte, produto, segmento).
- **PySpark:** desnecessário. São ~2,5–3 mil itens/dia e ~1M de histórico, e o BigQuery já faz inferência no SQL.
- **Prompt composto, montado por SQL para cada item:**
  - núcleo comum cacheável (schema, 8 naturezas, dois grãos, regra DDD, PII);
  - adapter por fonte;
  - shortlist da taxonomia (por produto + top-k por embedding);
  - few-shot do golden set.
- **Schema de saída unificado:**
  - `problema_canonico`, `natureza`, `postura`, `sentimento`, `descoberta_feature`;
  - `categorias[{id, primaria}]`, `evidencia` (≤ 15 palavras), `curadoria`, `confianca`.
  - Rótulo fora da lista vira `invalid_label`, nunca um default.
- **Clusterização (V3 antecipada):**
  1. Embedding do `problema_canonico`.
  2. `VECTOR_SEARCH` contra os centróides: similaridade alta → atribuição automática; zona cinza → juiz LLM barato com os top-3 clusters; similaridade baixa → pool de candidatos.
  3. O pool é clusterizado (HDBSCAN/aglomerativo), com piso de ≥3 conversas reais.
  4. Nomeação e merge por tier Sonnet, preservando a regra de clique.
  5. Os merges vão para o ledger.
  - Como o espaço vetorial é comum a todas as fontes, os clusters já saem cruzados entre fontes.
- **O que continua agêntico:** só o Cross (mensal) e um Aprofundador sob demanda.
  - A Leitura passa a ser um job em batch por cluster com movimento material.
  - Score e Tendência passam para SQL.
  - O Notion vira só render, com sync determinístico e os campos humanos voltando ao BQ.
  - Resultado: 5 sessões agênticas viram 1 pipeline, 1 job de síntese e 1 agente.

### 6.3 FinOps

**Alavancas, em ordem:**

1. Desacoplar a inferência: append-only, idempotente por `input_hash`, com status de erro e retry.
2. Dedupe por hash de input: −26% das chamadas (aquisição −99%, Keys-Off −95%, NPS −82%).
3. Não enviar NPS sem comentário.
4. Cache de prefixo sobre o template (91% do input). Falta verificar se o `AI.GENERATE` aproveita cache.
5. Shortlist e RAG da taxonomia: o template cai de ~30k para ~3–6k caracteres.
6. Limpar a transcrição do Zendesk (~4k caracteres em média).
7. Embeddings + cascata no Sense.
8. APIs em batch.
9. Re-síntese só com movimento material.
10. Higiene BigQuery (partition filter, clustering, MVs, labels).
11. Custo por item, fonte e etapa registrado no BQ.

**Cascata de modelos:**

| Tier | Quando entra | Modelo | Volume estimado |
|---|---|---|---|
| T0 | Regras/SQL: vazio, ruído, duplicado, picklist | Nenhum | ~25–35% |
| T1 | Extração | Gemini Flash-Lite no BQ (ou tier Haiku em batch) | ~60–70% |
| T2 | Escalonamento: curadoria, baixa confiança, divergência LLM × embedding | Gemini Flash ou tier Sonnet | ~5–10% |
| T3 | Nomear e fundir clusters, juiz da zona cinza, Leitura | Tier Sonnet, em batch e com cache | Dezenas/dia |
| T4 | Cross | Tier Opus | Mensal |

**Notas da cascata:**

- Para escalonar, usar a divergência entre LLM e embedding, não a confiança autodeclarada pelo LLM.
- Open source/self-hosting não compensa nesse volume; GPU ociosa custa mais que a API.

**Estimativas:**

- Suporte a 100% sai por ~US$ 30–40/mês, contra ~US$ 135/mês por amostra hoje.
- A Esteira A cai para ≤ ~US$ 20/mês.
- Reprocessar o histórico (~0,9M itens) custa hoje ~US$ 1,9 mil no Flash-Lite e ~US$ 22 mil a US$ 3/M. Com as otimizações, cai para **~US$ 300**.

---

## 7. Plano, métricas, decisões em aberto e riscos

**Fases (sem datas; prazo a dimensionar com os times):**

| Fase | Escopo | Critério de saída |
|---|---|---|
| 0. Alinhamento | Dono da taxonomia e do `voc_prompt`; golden set de ~150–200 itens por fonte | Dono definido e golden set rotulado |
| 1. Quick wins na VoC | Desacoplar inferência, retry, dedupe, NPS sem comentário, cache, assertions | Diff zero para consumidores e redução de tokens medida |
| 2. Core + taxonomia v1 em shadow | Core, bridges, dims de referência, prompt composto, view de compatibilidade | Eval ≥ baseline e explores de NPS intactos |
| 3. V3 de Suporte em shadow | Embeddings, `VECTOR_SEARCH`, pool, ledger, fato diária, síntese em batch | Paridade de top clusters com a V2 e custo dentro da meta |
| 4. Expansão + Cross | Demais fontes, `mart_voc_cross`, sync com o Notion | Cross gerando OPs a partir do mart |
| 5. Desativação + histórico | Desligar especialistas agênticos, reprocessar histórico, aposentar `full_prompt` | Série validada |

**Métricas e metas propostas** (a confirmar com a baseline da Fase 2):

- Cobertura de Suporte: 100%.
- Custo por item no Suporte: ≤ US$ 0,0015.
- Esteira A: ≤ US$ 20/mês.
- Balde genérico de categoria: < 5% (hoje 44% no recorte da Taxonomia v1; o teste da v1 chegou a 2,9%).
- Rótulo sem origem: 0%.
- Paridade V3 × V2: ≥ 80% dos top-20 clusters.
- Runs sem intervenção manual: ≥ 95%.

**Decisões em aberto:**

| Decisão | Recomendação | Fase |
|---|---|---|
| Dono da taxonomia e do `voc_prompt` | Dono único upstream (time de dados) | 0 |
| Modelo do T1 | Manter Gemini Flash-Lite e comparar no eval | 2 |
| Curadoria vs. rótulo forçado | Curadoria para análise de produto | 2 |
| Natureza × postura | Separar os eixos, usando os 8 valores da V2 | 2 |
| Limiares de similaridade | Calibrar no golden set | 3 |
| Papel do Notion | Render + retorno dos campos humanos | 4 |
| Histórico | Reprocessar | 5 |

**Riscos:**

- Limiares de embedding mal calibrados.
- Drift de centróides.
- Taxonomia sem dono.
- Conflito de sync com o Notion.
- Quebra de série na troca de taxonomia.
- `AI.GENERATE` sem cache de contexto.

---

## 8. Pendências e próximos passos

- **Acesso ao GitHub.** Os repositórios `ContaAzul/sense-platform` e `ContaAzul/documentation` são privados: retornam 404 sem login, não há conector do GitHub disponível e o Claude in Chrome não estava conectado. Caminhos possíveis:
  - instalar e logar o Claude in Chrome;
  - enviar um .zip ou os arquivos principais na conversa;
  - usar o Claude Code com os repositórios clonados localmente.
  - Objetivo: comparar a implementação real com a proposta To-Be e ajustar o Notion e o Miro onde houver divergência.
- **Miro.** Conferir se o widget Mermaid coube no frame "Sense 2.x · Arquitetura To-Be" e ajustar a borda se necessário.
- **Cache no `AI.GENERATE`.** Verificar se o BigQuery aproveita o cache de prefixo do Gemini no `AI.GENERATE`.
- **Esclarecimento sobre o As-Is.** A pergunta original falava em "1 orquestrador + N especialistas", mas o Notion mostra que a 2.0 roda sem orquestrador. Confirmar com o desenho do Frame 1 do Miro.

---

## 9. Premissas e referências de preço

- ~4 caracteres por token em português (estimativa).
- Gemini 3.1 Flash-Lite no Vertex: US$ 0,25 por milhão de tokens de input e US$ 1,50 por milhão de output (referência pública consultada em 21/10/2026).
- API do Claude:
  - A Batch API dá 50% de desconto em input e output.
  - A leitura de cache custa 0,1× o preço base de input; no Sonnet 5.5 e no Opus 5.5, cai para 0,05×.
  - Os dois descontos se acumulam (docs de pricing da Anthropic).
- O custo do Sense usa a convenção do time: 6,6e-6 US$/token (referência Sonnet US$ 3/US$ 15, mix 70/30).
- Todos os valores em US$ são estimativas de ordem de grandeza.

---

## Apêndice: queries usadas

**Esteira A (`dim_voc_full_category`, 30 dias, ~1,34 GB):**

```sql
WITH base AS (
  SELECT source, id_ferramenta,
    ANY_VALUE(llm_send_status) AS s,
    ANY_VALUE(LENGTH(full_prompt)) AS lp,
    ANY_VALUE(STRPOS(full_prompt, '<CNTX>')) AS tp,
    COUNT(*) AS n_rows,
    ANY_VALUE(TO_HEX(MD5(CONCAT(IFNULL(category,''),'|',IFNULL(reason,''),'|',
      IFNULL(sub_reason,''),'|',IFNULL(transcription,''),'|',IFNULL(problem_details,''))))) AS txt_hash
  FROM `contaazul-ssbi.gold_strategy.dim_voc_full_category`
  WHERE nk_event_date >= DATETIME(DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND nk_event_date < DATETIME(CURRENT_DATE())
  GROUP BY 1, 2
)
SELECT source,
  COUNT(*) AS itens,
  SUM(n_rows) AS linhas,
  COUNTIF(s = 'enviado_llm') AS enviados_llm,
  ROUND(AVG(IF(s = 'enviado_llm', lp, NULL))) AS media_chars_prompt,
  ROUND(AVG(IF(s = 'enviado_llm', tp, NULL))) AS media_chars_template,
  COUNT(DISTINCT IF(s = 'enviado_llm', txt_hash, NULL)) AS textos_distintos_enviados
FROM base
GROUP BY 1
ORDER BY itens DESC;
```

**Intercom (30 dias, ~46 MB):**

```sql
SELECT
  COUNT(*) / COUNT(DISTINCT DATE(created_at)) AS conversas_dia,
  COUNTIF(ai_issue_summary IS NOT NULL AND TRIM(ai_issue_summary) != '') / COUNT(*) AS pct_com_resumo,
  AVG(LENGTH(ai_issue_summary)) AS media_chars_resumo,
  COUNT(DISTINCT LOWER(TRIM(ai_issue_summary)))
    / COUNTIF(ai_issue_summary IS NOT NULL AND TRIM(ai_issue_summary) != '') AS pct_resumos_distintos
FROM `contaazul-ssbi.silver_serve.ingestion_intercom_conversations`
WHERE DATE(created_at) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
                           AND DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);
```
