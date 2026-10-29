-- =====================================================================================================
-- TESTE AUX-P v2: Gemini 3.1 flash-lite antes do agente Portal de Ideias (corrige o v1)
--
-- O QUE ESTAVA ERRADO NO v1 (achado ao ler os resultados de 29/10)
--   No backfill de prod, sense_ideas_portal_cluster_map.tema e sense_ideas_portal_cluster_meta.tema DISCORDAM em 930 dos 10.160 itens
--   (9,2%; 244 dos 1.764 clusters tem ao menos um item de outro tema). O v1 montou o catalogo e os ids curtos (K001...) pelo tema do
--   CLUSTER (meta), mas escolheu o catalogo de cada ideia pelo tema do ITEM (map). Nesses casos o cluster certo nao estava na lista que o
--   Gemini recebeu, e o id esperado apontava para outro cluster. Os numeros do v1 (cluster 32%, NEW correto 65%) nao sao confiaveis.
-- O QUE MUDA NO v2
--   1) O catalogo de cada ideia usa o tema do CLUSTER; a verdade e comparada por cluster_id (nao por id curto).
--   2) Nova variante 'completo': catalogo global sem roteamento por tema (~1,1 mil clusters), para medir quanto o roteamento por tema custa.
--   3) O texto bruto da resposta e guardado em cada tabela.
--   4) Todas as acuracias saem tambem restritas aos itens em que map.tema = meta.tema (subconjunto consistente).
-- Custo estimado: oraculo + predito ~US$ 0,4 (como no v1); completo ~7M tokens de entrada = ~US$ 2.
-- COMO RODAR: console do BigQuery, projeto contaazul-datalake-dev. Secoes 1 a 4, depois R1..R6 uma por vez.
-- =====================================================================================================

DECLARE model_endpoint STRING DEFAULT 'gemini-3.1-flash-lite';
DECLARE pct_amostra INT64 DEFAULT 4;   -- ~400 ideias, mesma amostra estavel do v1 (hash do id)
DECLARE catalogo_global STRING;

-- 1) Catalogo (clusters com 2+ ideias) com id curto por tema (kid) e id global (gid), ambos pelo tema do CLUSTER
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_portal_cat`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH sz AS (
  SELECT cluster_id, COUNT(*) AS tamanho
  FROM `contaazul-ssbi.tmp_data_analytics.sense_ideas_portal_cluster_map` GROUP BY 1
)
SELECT meta.tema, meta.cluster_id, sz.tamanho, meta.titulo_canonico,
  FORMAT('K%03d', ROW_NUMBER() OVER (PARTITION BY meta.tema ORDER BY meta.cluster_id)) AS kid,
  FORMAT('G%04d', ROW_NUMBER() OVER (ORDER BY meta.cluster_id)) AS gid
FROM `contaazul-ssbi.tmp_data_analytics.sense_ideas_portal_cluster_meta` meta
JOIN sz USING (cluster_id)
WHERE sz.tamanho >= 2;

CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_portal_cat_tema`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
SELECT tema, COUNT(*) AS n_clusters, STRING_AGG(CONCAT(kid, ' | ', titulo_canonico), '\n' ORDER BY kid) AS catalogo_txt
FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_cat` GROUP BY tema;

SET catalogo_global = (
  SELECT STRING_AGG(CONCAT(gid, ' | ', titulo_canonico), '\n' ORDER BY gid) FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_cat`);

-- 2) Populacao: a mesma amostra do v1, agora com o tema do item e o do cluster separados
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_portal_pop`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH sz AS (
  SELECT cluster_id, COUNT(*) AS tamanho
  FROM `contaazul-ssbi.tmp_data_analytics.sense_ideas_portal_cluster_map` GROUP BY 1
)
SELECT i.id, TRIM(i.title) AS titulo, SUBSTR(TRIM(i.body), 1, 1500) AS corpo,
  m.cluster_id AS cluster_verdade, m.tema AS tema_item, meta.tema AS tema_cluster, (m.tema = meta.tema) AS tema_consistente,
  sz.tamanho AS tamanho_cluster
FROM `contaazul-ssbi.silver_ideas_portal.ideas_portal` i
JOIN `contaazul-ssbi.tmp_data_analytics.sense_ideas_portal_cluster_map` m ON m.id = i.id
JOIN `contaazul-ssbi.tmp_data_analytics.sense_ideas_portal_cluster_meta` meta ON meta.cluster_id = m.cluster_id
JOIN sz ON sz.cluster_id = m.cluster_id
WHERE MOD(MOD(FARM_FINGERPRINT(i.id), 100) + 100, 100) < pct_amostra
  AND i.title IS NOT NULL AND TRIM(i.title) != '';

-- 3) T1: tema da ideia (lista fechada). Guarda o bruto.
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
- Escolha o tema da funcionalidade ou área a que a ideia se refere. Se nenhum serve, use "Outros / Não-ideia".
- Não invente tema.
</REGRAS>

<FORMATO>
Responda com um json no seguinte formato
{"tema": "Financeiro (Pagar/Receber)"}
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
  SELECT id, r.status AS llm_status, r.result AS bruto, COALESCE(REGEXP_EXTRACT(r.result, r'(?s)(\{.*?\})'), r.result) AS json_str FROM gerado
)
SELECT id, llm_status, bruto, SAFE.PARSE_JSON(json_str) IS NOT NULL AS json_valido, JSON_VALUE(json_str, '$.tema') AS tema_prev FROM lido;

-- 4) T2: escolher o cluster. modo: oraculo (tema verdadeiro do CLUSTER), predito (tema de T1), completo (catalogo global, sem tema)
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_portal_t2`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH base AS (
  SELECT p.id, modo, p.titulo, p.corpo,
    CASE modo WHEN 'oraculo' THEN p.tema_cluster WHEN 'predito' THEN t1.tema_prev ELSE 'GLOBAL' END AS tema_cat
  FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_pop` p
  JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_t1` t1 USING (id)
  CROSS JOIN UNNEST(['oraculo', 'predito', 'completo']) AS modo
), com_cat AS (
  SELECT b.*, IF(b.modo = 'completo', catalogo_global, c.catalogo_txt) AS catalogo_txt
  FROM base b LEFT JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_cat_tema` c ON c.tema = b.tema_cat
  WHERE b.modo = 'completo' OR c.tema IS NOT NULL
), gerado AS (
  SELECT id, modo, tema_cat, LENGTH(catalogo_txt) AS chars_catalogo,
    AI.GENERATE(
      CONCAT("""PAPEL: Você casa ideias de clientes de um ERP SaaS (Conta Azul) com um CATÁLOGO de ideias-tipo (clusters) já existentes.
TAREFA: Escolha o item do CATÁLOGO que descreve a MESMA ideia (mesma funcionalidade e mesmo pedido). Se nenhum descreve, responda NEW.

<CATALOGO>
""", catalogo_txt, """
</CATALOGO>

<REGRAS>
- cluster: o id do catálogo (ex.: "K012" ou "G0123") quando é a MESMA ideia. Só responda "NEW" se claramente nenhum item descreve o pedido.
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
  SELECT id, modo, tema_cat, chars_catalogo, r.status AS llm_status, r.result AS bruto,
    COALESCE(REGEXP_EXTRACT(r.result, r'(?s)(\{.*?\})'), r.result) AS json_str FROM gerado
), resp AS (
  SELECT id, modo, tema_cat, chars_catalogo, llm_status, bruto, SAFE.PARSE_JSON(json_str) IS NOT NULL AS json_valido,
    JSON_VALUE(json_str, '$.cluster') AS resposta
  FROM lido
)
-- converte o id curto de volta em cluster_id (por tema nos modos oraculo/predito; global no completo)
SELECT r.id, r.modo, r.tema_cat, r.chars_catalogo, r.llm_status, r.bruto, r.json_valido, r.resposta,
  CASE WHEN r.resposta = 'NEW' THEN 'NEW' ELSE c.cluster_id END AS cluster_prev_id
FROM resp r
LEFT JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_cat` c
  ON (r.modo = 'completo' AND c.gid = r.resposta) OR (r.modo != 'completo' AND c.tema = r.tema_cat AND c.kid = r.resposta);

-- =====================================================================================================
-- 5) RESULTADOS — rode uma consulta por vez
-- =====================================================================================================

-- R1) Populacao, consistencia de tema e validade do JSON
SELECT (SELECT COUNT(*) FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_pop`) AS ideias,
  (SELECT COUNTIF(NOT tema_consistente) FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_pop`) AS ideias_tema_item_diferente_do_cluster,
  (SELECT COUNTIF(tamanho_cluster = 1) FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_pop`) AS ideias_em_cluster_unitario,
  (SELECT COUNTIF(json_valido) FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t1`) AS t1_valido,
  (SELECT COUNTIF(json_valido) FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t2` WHERE modo = 'oraculo') AS oraculo_valido,
  (SELECT COUNTIF(json_valido) FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t2` WHERE modo = 'predito') AS predito_valido,
  (SELECT COUNTIF(json_valido) FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t2` WHERE modo = 'completo') AS completo_valido;

-- R2) T1: tema previsto contra o tema do ITEM (map) e contra o tema do CLUSTER (meta), geral e so nos consistentes
SELECT 'todas' AS grupo, COUNT(*) AS ideias,
  ROUND(100 * COUNTIF(t.tema_prev = p.tema_item) / COUNT(*), 1) AS pct_vs_tema_item,
  ROUND(100 * COUNTIF(t.tema_prev = p.tema_cluster) / COUNT(*), 1) AS pct_vs_tema_cluster
FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_pop` p JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_t1` t USING (id)
UNION ALL
SELECT 'tema item = tema cluster', COUNT(*), ROUND(100 * COUNTIF(t.tema_prev = p.tema_item) / COUNT(*), 1), ROUND(100 * COUNTIF(t.tema_prev = p.tema_cluster) / COUNT(*), 1)
FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_pop` p JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_t1` t USING (id) WHERE p.tema_consistente;

-- R3) Cluster por modo: acerto (cluster_id igual), falso NEW, cluster errado; NEW correto nas ideias de cluster unitario. Geral e no subconjunto consistente
SELECT t.modo, p.tema_consistente,
  COUNTIF(p.tamanho_cluster >= 2) AS ideias_cluster_ge2,
  COUNTIF(p.tamanho_cluster >= 2 AND t.cluster_prev_id = p.cluster_verdade) AS acertou,
  ROUND(100 * COUNTIF(p.tamanho_cluster >= 2 AND t.cluster_prev_id = p.cluster_verdade) / NULLIF(COUNTIF(p.tamanho_cluster >= 2), 0), 1) AS pct_acerto,
  COUNTIF(p.tamanho_cluster >= 2 AND t.cluster_prev_id = 'NEW') AS falso_new,
  COUNTIF(p.tamanho_cluster >= 2 AND t.cluster_prev_id != 'NEW' AND t.cluster_prev_id != p.cluster_verdade) AS cluster_errado,
  COUNTIF(p.tamanho_cluster = 1) AS ideias_unitarias,
  COUNTIF(p.tamanho_cluster = 1 AND t.cluster_prev_id = 'NEW') AS new_correto
FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t2` t JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_pop` p USING (id)
WHERE t.json_valido GROUP BY t.modo, p.tema_consistente ORDER BY t.modo, p.tema_consistente DESC;

-- R4) 40 discordancias (modo oraculo, tema consistente): titulo da ideia, cluster do backfill e cluster escolhido pelo Gemini, por cluster_id.
--     Rotular a mao: quem esta certo? (backfill / Gemini / ambos servem / nenhum)
SELECT p.titulo AS ideia, SUBSTR(p.corpo, 1, 300) AS descricao,
  (SELECT titulo_canonico FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_cat` c WHERE c.cluster_id = p.cluster_verdade) AS cluster_backfill,
  (SELECT titulo_canonico FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_cat` c WHERE c.cluster_id = t.cluster_prev_id) AS cluster_gemini
FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t2` t JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_pop` p USING (id)
WHERE t.modo = 'oraculo' AND p.tema_consistente AND p.tamanho_cluster >= 2 AND t.json_valido
  AND t.cluster_prev_id != 'NEW' AND t.cluster_prev_id != p.cluster_verdade
ORDER BY FARM_FINGERPRINT(p.id) LIMIT 40;

-- R5) Acerto por tamanho do cluster do backfill (modo oraculo, tema consistente)
SELECT CASE WHEN p.tamanho_cluster >= 20 THEN '20+' WHEN p.tamanho_cluster >= 5 THEN '5-19' WHEN p.tamanho_cluster >= 2 THEN '2-4' ELSE '1' END AS faixa_tamanho,
  COUNT(*) AS ideias,
  COUNTIF(IF(p.tamanho_cluster = 1, t.cluster_prev_id = 'NEW', t.cluster_prev_id = p.cluster_verdade)) AS acertos,
  ROUND(100 * COUNTIF(IF(p.tamanho_cluster = 1, t.cluster_prev_id = 'NEW', t.cluster_prev_id = p.cluster_verdade)) / COUNT(*), 1) AS pct
FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t2` t JOIN `contaazul-datalake-dev.dataform.tmp_aux_portal_pop` p USING (id)
WHERE t.modo = 'oraculo' AND p.tema_consistente AND t.json_valido GROUP BY 1 ORDER BY 1;

-- R6) Tamanho do catalogo e custo estimado (4 caracteres por token; US$ 0,25/M entrada, US$ 1,50/M saida)
SELECT modo, COUNT(*) AS chamadas, ROUND(AVG(chars_catalogo) / 4, 0) AS tokens_catalogo_medio,
  ROUND(SUM(chars_catalogo / 4 + 250) / 1e6 * 0.25 + COUNT(*) * 20 / 1e6 * 1.5, 2) AS usd_aprox
FROM `contaazul-datalake-dev.dataform.tmp_aux_portal_t2` GROUP BY modo ORDER BY modo;
