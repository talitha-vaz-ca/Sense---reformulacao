-- =====================================================================================================
-- TESTE AUX-P: Gemini 3.1 flash-lite como LLM auxiliar ANTES do agente Especialista Portal de Ideias
-- Verdade POR IDEIA: o mapa congelado do backfill (tmp_data_analytics.sense_ideas_portal_cluster_map) tem id -> cluster_id e tema
-- para ~10,2 mil ideias em ~1,76 mil clusters. E o unico dos agentes com rotulo por item, entao e o teste mais forte do plano.
--
-- COMO RODAR: console do BigQuery, projeto contaazul-datalake-dev (o MCP nao tem acesso ao dev nem ao AI.GENERATE).
--   1) Rode as secoes 1 a 4. 2) Rode as consultas R1..R6 uma por vez e cole os resultados na conversa.
-- Custo: ~400 ideias x 3 chamadas; catalogo por tema de ate alguns milhares de tokens. Estimativa: US$ 1 a 2. Nada de prod e alterado.
--
-- O QUE E MEDIDO
--   T1: tema da ideia (lista fechada de ~17 temas). T2: cluster dentro do tema (lista de titulos canonicos), com tema "oraculo" (isola a
--   capacidade de casar). T3: o mesmo com o tema PREDITO por T1 (pipeline completo). Acuracia contra o mapa do backfill.
-- SIMULACAO FIEL DE "IDEIA NOVA CONTRA CATALOGO CONGELADO"
--   O cluster de uma ideia que e a UNICA do cluster nao existiria no catalogo se ela fosse nova. Por isso o catalogo exclui clusters de
--   tamanho 1 e a resposta correta para essas ideias e NEW. Ideias em clusters de tamanho >= 2 devem cair no proprio cluster.
-- LIMITES
--   - O mapa do backfill foi feito pelo Claude; e referencia de consistencia, nao gabarito humano. Acuracia e um piso da qualidade.
--   - Catalogo completo por tema pode ser grande; se um tema passar de ~400 clusters, T2/T3 ficam caros (R6 mostra o maximo).
--   - Embeddings + busca vetorial (retrieval) para reduzir o catalogo por chamada ficam para a fase 2 deste teste.
-- =====================================================================================================

DECLARE model_endpoint STRING DEFAULT 'gemini-3.1-flash-lite';
DECLARE pct_amostra INT64 DEFAULT 4;   -- % das ideias (hash estavel): 4 = ~400 ideias

-- ----------------------------------------------------------------------------------------------------
-- 1) Catalogo por tema (clusters de tamanho >= 2), com ids curtos por tema para a resposta
-- ----------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_portal_cat`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH sz AS (
  SELECT cluster_id, COUNT(*) AS tamanho
  FROM `contaazul-ssbi.tmp_data_analytics.sense_ideas_portal_cluster_map` GROUP BY 1
)
SELECT meta.tema, meta.cluster_id, sz.tamanho, meta.titulo_canonico,
  FORMAT('K%03d', ROW_NUMBER() OVER (PARTITION BY meta.tema ORDER BY meta.cluster_id)) AS kid
FROM `contaazul-ssbi.tmp_data_analytics.sense_ideas_portal_cluster_meta` meta
JOIN sz USING (cluster_id)
WHERE sz.tamanho >= 2;

CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_portal_cat_tema`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
SELECT tema, COUNT(*) AS n_clusters,
  STRING_AGG(CONCAT(kid, ' | ', titulo_canonico), '\n' ORDER BY kid) AS catalogo_txt
FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_cat` GROUP BY tema;

-- ----------------------------------------------------------------------------------------------------
-- 2) Populacao de teste: amostra estavel de ideias com a verdade do backfill
-- ----------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_portal_pop`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH sz AS (
  SELECT cluster_id, COUNT(*) AS tamanho
  FROM `contaazul-ssbi.tmp_data_analytics.sense_ideas_portal_cluster_map` GROUP BY 1
)
SELECT i.id, TRIM(i.title) AS titulo, SUBSTR(TRIM(i.body), 1, 1500) AS corpo,
  m.cluster_id AS cluster_verdade, m.tema AS tema_verdade, sz.tamanho AS tamanho_cluster,
  IF(sz.tamanho >= 2, c.kid, 'NEW') AS resposta_esperada
FROM `contaazul-ssbi.silver_ideas_portal.ideas_portal` i
JOIN `contaazul-ssbi.tmp_data_analytics.sense_ideas_portal_cluster_map` m ON m.id = i.id
JOIN sz ON sz.cluster_id = m.cluster_id
LEFT JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_cat` c ON c.cluster_id = m.cluster_id
WHERE MOD(MOD(FARM_FINGERPRINT(i.id), 100) + 100, 100) < pct_amostra
  AND i.title IS NOT NULL AND TRIM(i.title) != '';

-- ----------------------------------------------------------------------------------------------------
-- 3) T1: tema (lista fechada = temas do catalogo do backfill)
-- ----------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_portal_t1`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH temas AS (
  SELECT STRING_AGG(DISTINCT tema, '\n' ORDER BY tema) AS lista FROM `contaazul-ssbi.tmp_data_analytics.sense_ideas_portal_cluster_meta`
), gerado AS (
  SELECT p.id,
    AI.GENERATE(
      CONCAT("""PAPEL: Você classifica ideias enviadas por clientes ao portal de ideias de um ERP SaaS (Conta Azul).
TAREFA: Escolha o TEMA da ideia, usando SOMENTE um valor da lista.

<TEMAS>
""", t.lista, """
</TEMAS>

<REGRAS>
- Escolha o tema da funcionalidade ou área a que a ideia se refere. Se nenhum serve, use "Outros".
- Não invente tema.
</REGRAS>

<FORMATO>
Responda com um json no seguinte formato
{"tema": "Financeiro"}
</FORMATO>

Antes de responder, valide que o JSON é válido. Retorne SOMENTE o JSON (sem formatação de Markdown). Aqui está a ideia:
Título: """, p.titulo, """
Descrição: """, IFNULL(p.corpo, '')),
      connection_id => 'us.vertex_connection',
      endpoint => model_endpoint,
      model_params => JSON '{"labels":{"ca_initiative":"voc_v0","ca_application_name":"bigquery"},"generation_config":{"thinking_config":{"thinking_budget":0},"temperature":0.0,"maxOutputTokens":300,"responseMimeType":"application/json"}}'
    ) AS r
  FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_pop` p CROSS JOIN temas t
), lido AS (
  SELECT id, r.status AS llm_status, COALESCE(REGEXP_EXTRACT(r.result, r'(?s)\{.*\}'), r.result) AS json_str FROM gerado
)
SELECT id, llm_status, SAFE.PARSE_JSON(json_str) IS NOT NULL AS json_valido, JSON_VALUE(json_str, '$.tema') AS tema_prev FROM lido;

-- ----------------------------------------------------------------------------------------------------
-- 4) T2 (tema oraculo) e T3 (tema predito por T1): escolher o cluster dentro do tema, ou NEW
-- ----------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_portal_t2`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH base AS (
  SELECT p.id, modo, IF(modo = 'oraculo', p.tema_verdade, t1.tema_prev) AS tema_cat, p.titulo, p.corpo
  FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_pop` p
  JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_t1` t1 USING (id)
  CROSS JOIN UNNEST(['oraculo', 'predito']) AS modo
), com_cat AS (
  SELECT b.*, c.catalogo_txt, c.n_clusters
  FROM base b JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_cat_tema` c ON c.tema = b.tema_cat
), gerado AS (
  SELECT id, modo, tema_cat, n_clusters, LENGTH(catalogo_txt) AS chars_catalogo,
    AI.GENERATE(
      CONCAT("""PAPEL: Você casa ideias de clientes de um ERP SaaS (Conta Azul) com um CATÁLOGO de ideias-tipo (clusters) já existentes.
TAREFA: Escolha o item do CATÁLOGO que descreve a MESMA ideia (mesma funcionalidade e mesmo pedido). Se nenhum descreve, responda NEW.

<CATALOGO>
""", catalogo_txt, """
</CATALOGO>

<REGRAS>
- cluster: o id do catálogo (ex.: "K012") quando é a MESMA ideia. Só responda "NEW" se claramente nenhum item descreve o pedido.
- Mesma área do produto não basta: o pedido específico tem de ser o mesmo.
- Nunca invente id fora do catálogo.
</REGRAS>

<FORMATO>
Responda com um json no seguinte formato
{"cluster": "K012"}
</FORMATO>

Antes de responder, valide que o JSON é válido. Retorne SOMENTE o JSON (sem formatação de Markdown). Aqui está a ideia:
Título: """, titulo, """
Descrição: """, IFNULL(corpo, '')),
      connection_id => 'us.vertex_connection',
      endpoint => model_endpoint,
      model_params => JSON '{"labels":{"ca_initiative":"voc_v0","ca_application_name":"bigquery"},"generation_config":{"thinking_config":{"thinking_budget":0},"temperature":0.0,"maxOutputTokens":300,"responseMimeType":"application/json"}}'
    ) AS r
  FROM com_cat
), lido AS (
  SELECT id, modo, tema_cat, n_clusters, chars_catalogo, r.status AS llm_status,
    COALESCE(REGEXP_EXTRACT(r.result, r'(?s)\{.*\}'), r.result) AS json_str FROM gerado
)
SELECT id, modo, tema_cat, n_clusters, chars_catalogo, llm_status, SAFE.PARSE_JSON(json_str) IS NOT NULL AS json_valido,
  JSON_VALUE(json_str, '$.cluster') AS cluster_prev
FROM lido;

-- =====================================================================================================
-- 5) RESULTADOS — rode uma consulta por vez
-- =====================================================================================================

-- R1) Populacao e diagnostico (JSON valido por etapa)
SELECT (SELECT COUNT(*) FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_pop`) AS ideias,
  (SELECT COUNTIF(json_valido) FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t1`) AS t1_valido,
  (SELECT COUNTIF(json_valido) FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t2` WHERE modo = 'oraculo') AS t2_oraculo_valido,
  (SELECT COUNTIF(json_valido) FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t2` WHERE modo = 'predito') AS t3_predito_valido,
  (SELECT COUNTIF(tamanho_cluster = 1) FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_pop`) AS ideias_em_cluster_unitario;

-- R2) T1: acuracia do tema contra o mapa do backfill, geral e por tema (os 10 maiores)
SELECT p.tema_verdade, COUNT(*) AS ideias, COUNTIF(t.tema_prev = p.tema_verdade) AS acertos,
  ROUND(100 * COUNTIF(t.tema_prev = p.tema_verdade) / COUNT(*), 1) AS pct
FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_pop` p JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_t1` t USING (id)
GROUP BY ROLLUP(p.tema_verdade) ORDER BY ideias DESC LIMIT 12;

-- R3) T2 oraculo e T3 predito: acuracia do cluster (ideias em cluster >= 2) e tratamento de NEW (ideias em cluster unitario)
SELECT t.modo,
  COUNTIF(p.tamanho_cluster >= 2) AS ideias_cluster_ge2,
  COUNTIF(p.tamanho_cluster >= 2 AND t.cluster_prev = p.resposta_esperada) AS acertou_cluster,
  ROUND(100 * COUNTIF(p.tamanho_cluster >= 2 AND t.cluster_prev = p.resposta_esperada) / NULLIF(COUNTIF(p.tamanho_cluster >= 2), 0), 1) AS pct_cluster,
  COUNTIF(p.tamanho_cluster >= 2 AND t.cluster_prev = 'NEW') AS falso_new,
  COUNTIF(p.tamanho_cluster = 1) AS ideias_unitarias,
  COUNTIF(p.tamanho_cluster = 1 AND t.cluster_prev = 'NEW') AS new_correto,
  ROUND(100 * COUNTIF(p.tamanho_cluster = 1 AND t.cluster_prev = 'NEW') / NULLIF(COUNTIF(p.tamanho_cluster = 1), 0), 1) AS pct_new_correto
FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t2` t JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_pop` p USING (id)
GROUP BY t.modo;

-- R4) Erros de cluster: Gemini escolheu OUTRO cluster do catalogo (nao NEW). Titulos lado a lado para julgamento humano
SELECT p.titulo AS ideia, p.corpo AS descricao,
  (SELECT titulo_canonico FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_cat` c WHERE c.tema = t.tema_cat AND c.kid = p.resposta_esperada) AS cluster_backfill,
  (SELECT titulo_canonico FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_cat` c WHERE c.tema = t.tema_cat AND c.kid = t.cluster_prev) AS cluster_gemini
FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t2` t JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_pop` p USING (id)
WHERE t.modo = 'oraculo' AND p.tamanho_cluster >= 2 AND t.cluster_prev != 'NEW' AND t.cluster_prev != p.resposta_esperada
ORDER BY FARM_FINGERPRINT(p.id) LIMIT 30;

-- R5) Concordancia por tamanho de cluster (o casamento piora quando o cluster e grande ou pequeno?)
SELECT CASE WHEN p.tamanho_cluster >= 20 THEN '20+' WHEN p.tamanho_cluster >= 5 THEN '5-19' WHEN p.tamanho_cluster >= 2 THEN '2-4' ELSE '1' END AS faixa_tamanho,
  COUNT(*) AS ideias, COUNTIF(t.cluster_prev = p.resposta_esperada) AS acertos,
  ROUND(100 * COUNTIF(t.cluster_prev = p.resposta_esperada) / COUNT(*), 1) AS pct
FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t2` t JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_pop` p USING (id)
WHERE t.modo = 'oraculo' GROUP BY 1 ORDER BY 1;

-- R6) Tamanho dos catalogos por tema e custo estimado (4 caracteres por token; US$ 0,25/M entrada, US$ 1,50/M saida)
SELECT tema_cat, ANY_VALUE(n_clusters) AS clusters_no_tema, ANY_VALUE(chars_catalogo) AS chars_catalogo,
  ROUND(ANY_VALUE(chars_catalogo) / 4, 0) AS tokens_catalogo, COUNT(*) AS chamadas
FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t2` WHERE modo = 'oraculo' GROUP BY tema_cat ORDER BY tokens_catalogo DESC;

SELECT ROUND(SUM(chars_catalogo / 4 + 250) / 1e6 * 0.25 + COUNT(*) * 20 / 1e6 * 1.5, 2) AS usd_t2_t3_aprox, COUNT(*) AS chamadas
FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t2`;
