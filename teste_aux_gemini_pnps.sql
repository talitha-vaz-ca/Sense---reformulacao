-- =====================================================================================================
-- TESTE AUX-N: Gemini 3.1 flash-lite como LLM auxiliar ANTES do agente Especialista pNPS
-- Mes fechado: setembro/2026. Compara a rotulagem comentario a comentario do Gemini com o que o agente pNPS PROD gravou
-- na DB de Sinais (Notion, ds 44f63463..., "Mes de referencia" 2026-09-01: 28 sinais, 408 mencoes Pro+Mais).
--
-- COMO RODAR: console do BigQuery, projeto contaazul-datalake-dev (o MCP nao tem acesso ao dev nem ao AI.GENERATE).
--   1) Rode as secoes 1 a 3. 2) Rode as consultas R1..R7 uma por vez e cole os resultados na conversa.
-- Custo: ~342 chamadas de ~1,3 mil tokens = ~0,45M tokens de entrada, menos de US$ 0,2. Nada de prod e alterado.
--
-- POR QUE ESTE TESTE E DIFERENTE DO SUPORTE
--   O texto do pNPS e minusculo (media 72 caracteres, p90 170, ~340 comentarios/mes). Nao ha economia de tokens a buscar no Claude:
--   o gargalo do agente e o METODO (CASE/REGEXP desenhado pelo LLM + auditoria do residuo; a run 2 levou 34 min e truncou ~9 de 27 sinais).
--   A hipotese aqui e de QUALIDADE e ESTABILIDADE: o Gemini rotula cada comentario nos baldes N1/N2 e deixa o agente so com N3 e Leitura.
-- LIMITES
--   - Verdade por SINAL (agente nao persiste comentario->sinal; "DB de Comentarios" e evolucao futura). Comparacao em N1 e N2 (multi-rotulo).
--   - As 13 opcoes de N2 abaixo sao as vistas nos sinais de set/26 + "Risco de churn (flag)". O schema do agente tem 16 N2: complete a lista
--     (linha marcada ###) antes de rodar para o teste valer.
--   - O agente conta so comentarios "uteis" (de qualquer nota). Aqui entram todos os comentarios nao vazios do pNPS/Survicate do mes.
-- =====================================================================================================

DECLARE mes_ini DATE DEFAULT DATE '2026-09-01';
DECLARE mes_fim DATE DEFAULT DATE '2026-10-01';
DECLARE model_endpoint STRING DEFAULT 'gemini-3.1-flash-lite';
DECLARE n_reps INT64 DEFAULT 1;   -- 2 para medir autoconsistencia (R6)

-- ----------------------------------------------------------------------------------------------------
-- 1) Populacao: comentarios do mes (mesmo filtro do agente: pNPS + Survicate)
-- ----------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_pnps_pop`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
SELECT sk_nps_survey, survey_name_standard, nps_answer, nps_classification, customer_type, partner_type,
  TRIM(nps_comment) AS comentario
FROM `contaazul-ssbi.gold_nps.fact_nps_survey`
WHERE nps_tool = 'Survicate' AND nps_type = 'pNPS'
  AND DATE(nk_date) >= mes_ini AND DATE(nk_date) < mes_fim
  AND nps_comment IS NOT NULL AND TRIM(nps_comment) != '';

-- ----------------------------------------------------------------------------------------------------
-- 2) Verdade da set/26 por N2 (soma de Pro + Mais Mencoes dos sinais do agente, multi-rotulo) e N1 de cada N2
--    Fonte: DB Sinais pNPS prod (Notion), leitura em 29/10/2026. Total = 408 mencoes sobre ~342 comentarios.
-- ----------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_pnps_verdade`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
SELECT * FROM UNNEST([
  STRUCT('Facilidade / praticidade' AS n2, 'Produto' AS n1, 92 AS mencoes_agente),
  STRUCT('Suporte lento / não resolve', 'Suporte & Atendimento', 36),
  STRUCT('Recursos faltando', 'Produto', 75),
  STRUCT('Bugs & instabilidade', 'Produto', 82),
  STRUCT('Sem tema', 'Sem tema', 31),
  STRUCT('Usabilidade & experiência', 'Produto', 27),
  STRUCT('Preço alto', 'Preços & Planos', 20),
  STRUCT('Onboarding & treinamento', 'Produto', 15),
  STRUCT('Elogio a recurso / IA', 'Produto', 12),
  STRUCT('Elogio a suporte/gerente', 'Suporte & Atendimento', 7),
  STRUCT('Falta atendimento humano', 'Suporte & Atendimento', 6),
  STRUCT('Reajuste', 'Preços & Planos', 4),
  STRUCT('Pós-venda & promessas', 'Relacionamento & Programa', 1)
]);

-- ----------------------------------------------------------------------------------------------------
-- 3) Chamada auxiliar: 1 por comentario, listas FECHADAS de N1 e N2 (a mesma regra do agente: multi-rotulo, nada fora das listas)
-- ----------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_pnps_gem`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH gerado AS (
  SELECT sk_nps_survey, rep,
    AI.GENERATE(
      CONCAT("""PAPEL: Você classifica comentários de uma pesquisa NPS de um ERP SaaS (Conta Azul, CA Pro e CA Mais).
TAREFA: Para o COMENTÁRIO abaixo, devolva os campos pedidos, usando SOMENTE os valores das listas.

<N1>
Produto | Suporte & Atendimento | Preços & Planos | Relacionamento & Programa | Sem tema
</N1>

<N2>
Facilidade / praticidade: encantamento difuso ("prático", "fácil", "resolve minha vida"), sem nomear funcionalidade.
Elogio a recurso / IA: elogia uma funcionalidade ou a IA, nomeando.
Elogio a suporte/gerente: elogia atendimento, suporte ou gerente de parceria.
Recursos faltando: pede funcionalidade que não existe ou não cobre o caso (relatório, estoque, API, CRM, orçamento/OS, compras, importação...).
Bugs & instabilidade: algo quebra, trava, diverge ou é lento (emissão de NF/boleto, conciliação, integração...).
Usabilidade & experiência: existe, mas é difícil de achar ou usar (interface, fluxo, modo escuro...).
Onboarding & treinamento: dificuldade de começar, aprender ou treinar.
Suporte lento / não resolve: reclama do suporte (demora, não resolve).
Falta atendimento humano: quer falar com pessoa e só encontra bot ou fila.
Preço alto: preço ou custo-benefício ruim.
Reajuste: aumento ou reajuste de valor, renovação.
Pós-venda & promessas: promessa feita na venda e não cumprida, pós-venda.
Risco de churn (flag): diz que vai cancelar ou trocar de sistema (use em ADIÇÃO a outro N2, nunca sozinho).
Sem tema: vazio de conteúdo ("ok", "bom", "nada a dizer").
</N2>
### acrescente aqui os N2 do schema que faltam (o agente tem 16)

<REGRAS>
- n2: de 1 a 2 valores da lista N2 (multi-rótulo só quando o comentário trata de dois assuntos distintos). Nunca invente valor.
- n1: o macrotema de cada n2 (lista N1), na mesma ordem.
- Se o cliente NOMEIA uma funcionalidade ou cenário, prefira o N2 específico (Recursos faltando, Bugs & instabilidade, Usabilidade) e escreva o cenário em "cenario" (até 6 palavras, ex.: "emissão de NF falha").
- Se não nomeia, use o balde genérico: encantamento difuso = "Facilidade / praticidade"; vazio = "Sem tema".
- valencia: UM de Elogio, Crítica, Gap, Misto.
- superficie: onde a dor mora: "CA Pro", "CA Mais", "Programa de parceria" ou "Suporte".
- Não confunda a nota com o conteúdo: julgue pelo texto.
</REGRAS>

<FORMATO>
Responda com um json no seguinte formato
{"n1": ["Produto"], "n2": ["Bugs & instabilidade"], "cenario": "emissão de NF falha", "valencia": "Crítica", "superficie": "CA Pro"}
</FORMATO>

Antes de responder, valide que o JSON é válido. Retorne SOMENTE o JSON (sem formatação de Markdown). Aqui está o comentário (nota """, CAST(nps_answer AS STRING), """):
""", comentario),
      connection_id => 'us.vertex_connection',
      endpoint => model_endpoint,
      model_params => JSON '{"labels":{"ca_initiative":"voc_v0","ca_application_name":"bigquery"},"generation_config":{"thinking_config":{"thinking_budget":0},"temperature":0.0,"maxOutputTokens":500,"responseMimeType":"application/json"}}'
    ) AS r
  FROM `contaazul-datalake-dev.dataform.tmp_aux_pnps_pop`, UNNEST(GENERATE_ARRAY(1, n_reps)) AS rep
), lido AS (
  SELECT sk_nps_survey, rep, r.status AS llm_status, r.result AS bruto, COALESCE(REGEXP_EXTRACT(r.result, r'(?s)(\{.*?\})'), r.result) AS json_str FROM gerado
)
SELECT sk_nps_survey, rep, llm_status, bruto, SAFE.PARSE_JSON(json_str) IS NOT NULL AS json_valido,
  JSON_VALUE_ARRAY(json_str, '$.n1') AS n1, JSON_VALUE_ARRAY(json_str, '$.n2') AS n2,
  JSON_VALUE(json_str, '$.cenario') AS cenario, JSON_VALUE(json_str, '$.valencia') AS valencia,
  JSON_VALUE(json_str, '$.superficie') AS superficie
FROM lido;

-- =====================================================================================================
-- 4) RESULTADOS — rode uma consulta por vez
-- =====================================================================================================

-- R1) Populacao e diagnostico das chamadas (confere se a populacao bate ~334-342 comentarios; JSON valido; N2 fora da lista)
WITH t AS (
  SELECT g.sk_nps_survey, g.json_valido,
    COUNTIF(x IS NOT NULL AND v.n2 IS NULL AND x != 'Risco de churn (flag)') AS n_fora_da_lista
  FROM `contaazul-datalake-dev.dataform.tmp_aux_pnps_gem` g
  LEFT JOIN UNNEST(g.n2) AS x
  LEFT JOIN `contaazul-datalake-dev.dataform.tmp_aux_pnps_verdade` v ON v.n2 = x
  WHERE g.rep = 1 GROUP BY 1, 2
)
SELECT (SELECT COUNT(*) FROM `contaazul-datalake-dev.dataform.tmp_aux_pnps_pop`) AS comentarios,
  COUNT(*) AS chamadas, COUNTIF(json_valido) AS json_valido, COUNTIF(n_fora_da_lista > 0) AS com_n2_fora_da_lista
FROM t;

-- R2) N2: mencoes do Gemini (multi-rotulo) vs mencoes do agente em set/26
WITH g AS (
  SELECT x AS n2, COUNT(*) AS gem
  FROM `contaazul-datalake-dev.dataform.tmp_aux_pnps_gem`, UNNEST(n2) AS x
  WHERE rep = 1 AND json_valido GROUP BY 1
), j AS (
  SELECT v.n2, v.n1, v.mencoes_agente AS agente, IFNULL(g.gem, 0) AS gemini
  FROM `contaazul-datalake-dev.dataform.tmp_aux_pnps_verdade` v LEFT JOIN g USING (n2)
), r AS (SELECT *, RANK() OVER (ORDER BY agente DESC) AS rk_a, RANK() OVER (ORDER BY gemini DESC) AS rk_g FROM j)
SELECT n2, n1, agente, gemini, gemini - agente AS dif, ROUND(100 * (gemini - agente) / agente, 0) AS dif_pct, rk_a, rk_g
FROM r ORDER BY agente DESC;

-- R2b) Resumo da comparacao em N2: correlacao, soma, erro relativo, top-5
WITH g AS (
  SELECT x AS n2, COUNT(*) AS gem
  FROM `contaazul-datalake-dev.dataform.tmp_aux_pnps_gem`, UNNEST(n2) AS x
  WHERE rep = 1 AND json_valido GROUP BY 1
), j AS (
  SELECT v.n2, v.mencoes_agente AS agente, IFNULL(g.gem, 0) AS gemini
  FROM `contaazul-datalake-dev.dataform.tmp_aux_pnps_verdade` v LEFT JOIN g USING (n2)
), r AS (SELECT *, RANK() OVER (ORDER BY agente DESC) AS rk_a, RANK() OVER (ORDER BY gemini DESC) AS rk_g FROM j)
SELECT SUM(agente) AS soma_agente, SUM(gemini) AS soma_gemini,
  ROUND(CORR(agente, gemini), 3) AS pearson, ROUND(CORR(rk_a, rk_g), 3) AS spearman_aprox,
  COUNTIF(rk_a <= 5 AND rk_g <= 5) AS top5_em_comum,
  ROUND(AVG(IF(agente >= 10, ABS(gemini - agente) / agente, NULL)), 3) AS erro_relativo_medio_n2_ge10
FROM r;

-- R3) N1 (macrotema): distribuicao Gemini vs agente
WITH g AS (
  SELECT x AS n1, COUNT(*) AS gem
  FROM `contaazul-datalake-dev.dataform.tmp_aux_pnps_gem`, UNNEST(n1) AS x
  WHERE rep = 1 AND json_valido GROUP BY 1
), a AS (
  SELECT n1, SUM(mencoes_agente) AS agente FROM `contaazul-datalake-dev.dataform.tmp_aux_pnps_verdade` GROUP BY 1
)
SELECT COALESCE(a.n1, g.n1) AS n1, a.agente, g.gem AS gemini FROM a FULL JOIN g USING (n1) ORDER BY agente DESC;

-- R4) Valencia e superficie (campos que o agente grava por sinal; so distribuicao, nao ha verdade por comentario)
SELECT valencia, superficie, COUNT(*) AS comentarios
FROM `contaazul-datalake-dev.dataform.tmp_aux_pnps_gem` WHERE rep = 1 AND json_valido GROUP BY 1, 2 ORDER BY comentarios DESC;

-- R5) Cenarios nomeados: o que o agente teria de "abrir" em N3 dentro de Bugs & instabilidade e Recursos faltando
--     (set/26 do agente: Emissao de NF com falhas 16, Conciliacao bancaria falha 15, Falhas e limitacoes de integracao 13, Faltam relatorios 14,
--      Controle de estoque 6, Orcamentos/OS 6, Emissao de boleto com falhas 5, NF por parcela/em bloco 4, Compras 2 ...)
SELECT n2_unico AS n2, LOWER(cenario) AS cenario, COUNT(*) AS comentarios
FROM `contaazul-datalake-dev.dataform.tmp_aux_pnps_gem`, UNNEST(n2) AS n2_unico
WHERE rep = 1 AND json_valido AND n2_unico IN ('Bugs & instabilidade', 'Recursos faltando') AND cenario IS NOT NULL AND cenario != ''
GROUP BY 1, 2 ORDER BY comentarios DESC LIMIT 60;

-- R6) Autoconsistencia (so se n_reps = 2): mesmo N2 nas duas repeticoes?
SELECT COUNT(*) AS comentarios,
  COUNTIF(ARRAY_TO_STRING(ARRAY(SELECT x FROM UNNEST(a.n2) x ORDER BY x), '|') = ARRAY_TO_STRING(ARRAY(SELECT x FROM UNNEST(b.n2) x ORDER BY x), '|')) AS mesmo_n2
FROM `contaazul-datalake-dev.dataform.tmp_aux_pnps_gem` a
JOIN `contaazul-datalake-dev.dataform.tmp_aux_pnps_gem` b ON a.sk_nps_survey = b.sk_nps_survey AND a.rep = 1 AND b.rep = 2;

-- R7) Amostra de 50 comentarios para ROTULO HUMANO (inicio do conjunto rotulado do pNPS) com a decisao do Gemini
SELECT p.sk_nps_survey, p.nps_answer, p.comentario, ARRAY_TO_STRING(g.n2, ' | ') AS n2_gemini, g.cenario, g.valencia, g.superficie
FROM `contaazul-datalake-dev.dataform.tmp_aux_pnps_gem` g
JOIN `contaazul-datalake-dev.dataform.tmp_aux_pnps_pop` p USING (sk_nps_survey)
WHERE g.rep = 1 AND g.json_valido
ORDER BY FARM_FINGERPRINT(p.sk_nps_survey) LIMIT 50;
