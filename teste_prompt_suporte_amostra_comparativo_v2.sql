-- Teste comparativo v2: chamada A (prompt de producao sem alteracao, 2 repeticoes) + chamada B (so os campos novos).
--
-- O que muda em relacao a v1 (teste_prompt_suporte_amostra_comparativo.sql):
--   * Sem output_schema. A v1 usou output_schema com gemini-3.1 e 17 de 66 chamadas voltaram "Failed to parse" e 14 vieram
--     com campos nulos ou com texto de raciocinio dentro de tipo_de_incidente_gemini. Aqui a chamada e igual a de producao:
--     o JSON sai do proprio texto (formato do prompt) e e parseado depois, com responseMimeType application/json.
--   * Guarda r.status, finishReason e o texto cru, para diagnosticar cada falha (MAX_TOKENS? JSON invalido? erro de API?).
--   * Duas chamadas separadas por ticket, em vez de um bloco novo dentro do prompt de producao:
--       A_rep1 / A_rep2  = full_prompt gravado, sem alteracao (mede a autoconsistencia e a concordancia com o gravado)
--       B                = so natureza, problema_canonico, descoberta_feature, evidencia (nao contamina tipo/sentimento)
--   * Categoria validada contra a lista do prompt por linha exata (antes era substring, o que aprovava "Valor do plano").
--   * Todo percentual sai com o denominador explicito: sobre os 33 tickets e sobre os que tiveram JSON valido.
--
-- Mesma amostra de 33 tickets (3 originais, 12 do tema boleto/Pix, 18 estratificados). Filtro de particao obrigatorio.

DECLARE model_endpoint STRING DEFAULT 'gemini-3.1-flash-lite';
-- Alternativa com URL completa, como no esboco do doc de arquitetura:
-- SET model_endpoint = 'https://aiplatform.googleapis.com/v1/projects/contaazul-datalake-dev/locations/global/publishers/google/models/gemini-3.1-flash-lite';

CREATE TEMP TABLE resultado AS
WITH amostra AS (
  SELECT id_ferramenta, grupo FROM UNNEST([
    STRUCT('6189021' AS id_ferramenta, 'O' AS grupo), ('6188174','O'), ('6178426','O'),
    ('6212390','A'), ('6191974','A'), ('6182188','A'), ('6192237','A'), ('6191979','A'), ('6203002','A'),
    ('6203133','A'), ('6206529','A'), ('6213525','A'), ('6193722','A'), ('6210991','A'), ('6199844','A'),
    ('6205991','B'), ('6202405','B'), ('6205869','B'), ('6219033','B'), ('6207716','B'), ('6205873','B'),
    ('6202245','B'), ('6216173','B'), ('6194451','B'), ('6207605','B'), ('6197574','B'), ('6221156','B'),
    ('6212743','B'), ('6187391','B'), ('6206640','B'), ('6201432','B'), ('6218479','B'), ('6190987','B')
  ])
), prod AS (
  SELECT d.id_ferramenta, a.grupo,
    ANY_VALUE(d.full_prompt) AS fp,
    ANY_VALUE(d.sentiment) AS prod_sentimento,
    ANY_VALUE(d.macro_theme) AS prod_macrotema,
    ANY_VALUE(d.incident_type_gemini) AS prod_tipo,
    ARRAY_AGG(DISTINCT d.category_gemini IGNORE NULLS) AS prod_cats
  FROM `contaazul-ssbi.gold_strategy.dim_voc_full_category` d
  JOIN amostra a USING (id_ferramenta)
  WHERE d.source = 'zendesk' AND d.llm_send_status = 'enviado_llm'
    AND d.nk_event_date >= DATETIME('2026-10-16') AND d.nk_event_date < DATETIME('2026-10-28')
  GROUP BY 1, 2
), chamadas AS (
  SELECT id_ferramenta, grupo, CONCAT('A_rep', CAST(rep AS STRING)) AS chamada, fp AS prompt
  FROM prod, UNNEST([1, 2]) AS rep
  UNION ALL
  SELECT id_ferramenta, grupo, 'B',
    CONCAT("""PAPEL: Você é um especialista em Voice of Customer de um ERP SaaS.
TAREFA: Para o atendimento abaixo, extraia os campos pedidos seguindo as regras.

<NATUREZA>
Escolha UM valor para o tipo de trabalho que o pedido exige do time:
bug: funciona errado, parou de funcionar, dá erro ou o resultado diverge do esperado.
usabilidade: a funcionalidade existe e resolve, mas o cliente não a encontra ou o caminho é caro.
gap: não existe no produto, ou existe e não cobre o caso (limite, campo, regra).
dúvida: pergunta conceitual ou de regra de negócio. Se o produto se comporta como foi desenhado e o cliente só não conhecia a regra, é dúvida, não bug.
infra: acesso, login, indisponibilidade, lentidão generalizada.
comercial: preço, plano, contrato, cobrança da assinatura, cancelamento.
operacional: o cliente cobra status ou prazo do próprio chamado.
ruído: saudação, teste, abandono, nada classificável.
Se houver mais de uma natureza, vale a que gera trabalho de engenharia, nesta ordem: bug, infra, usabilidade, gap.
</NATUREZA>

<REGRAS>
- problema_canonico: em bug, gap e usabilidade, o problema específico na linguagem do cliente, em uma frase, sem número de venda, valor, nome ou e-mail. Nos demais casos, vazio.
- descoberta_feature: preencha SOMENTE se o cliente pergunta como fazer, onde achar ou se é possível, sem relatar defeito. Em bug, deixe vazio.
- evidencia: trecho literal de até 15 palavras de uma mensagem do CLIENTE, sem nome, CPF, CNPJ, e-mail ou telefone.
- Mensagens de bot e de atendente são contexto de resolução, nunca o motivo do contato.
</REGRAS>

<FORMATO>
Responda com um json no seguinte formato
{
"natureza": "bug",
"problema_canonico": "Pagamento de boleto não baixado automaticamente",
"descoberta_feature": "",
"evidencia": "meu cliente pagou o boleto mas não deu baixa"
}
</FORMATO>

Antes de responder, valide que o JSON é válido. Retorne SOMENTE o JSON (sem formatação de Markdown). Aqui está o comentário:
""", SUBSTR(fp, STRPOS(fp, '<CNTX>')))
  FROM prod
), gerado AS (
  SELECT id_ferramenta, grupo, chamada,
    AI.GENERATE(
      prompt,
      connection_id => 'us.vertex_connection',
      endpoint => model_endpoint,
      model_params => JSON '{"labels":{"ca_initiative":"voc_v0","ca_application_name":"bigquery"},"generation_config":{"thinking_config":{"thinking_budget":0},"temperature":0.0,"maxOutputTokens":2000,"responseMimeType":"application/json"}}'
    ) AS r
  FROM chamadas
), lido AS (
  SELECT id_ferramenta, grupo, chamada,
    r.status AS llm_status,
    SAFE.STRING(SAFE.PARSE_JSON(TO_JSON_STRING(r.full_response)).candidates[0].finishReason) AS finish_reason,
    LENGTH(r.result) AS len_resposta,
    COALESCE(REGEXP_EXTRACT(r.result, r'(?s)\{.*\}'), r.result) AS json_str
  FROM gerado
), campos AS (
  SELECT *, SAFE.PARSE_JSON(json_str) IS NOT NULL AS json_valido,
    JSON_VALUE(json_str, '$.macrotema') AS macrotema,
    JSON_VALUE(json_str, '$.tipo_de_incidente_gemini') AS tipo,
    JSON_VALUE(json_str, '$.sentimento') AS sentimento,
    JSON_VALUE(json_str, '$.subcategoria') AS subcategoria,
    JSON_VALUE(json_str, '$.Resumo_do_Incidente_gemini') AS resumo,
    JSON_VALUE(json_str, '$.natureza') AS natureza,
    JSON_VALUE(json_str, '$.problema_canonico') AS problema_canonico,
    JSON_VALUE(json_str, '$.descoberta_feature') AS descoberta_feature,
    ARRAY_LENGTH(SPLIT(JSON_VALUE(json_str, '$.evidencia'), ' ')) AS palavras_evidencia
  FROM lido
)
SELECT c.id_ferramenta, c.grupo, c.chamada, c.llm_status, c.finish_reason, c.len_resposta, c.json_valido,
  p.prod_macrotema, c.macrotema, p.prod_tipo, c.tipo, p.prod_sentimento, c.sentimento,
  ARRAY_TO_STRING(p.prod_cats, ' | ') AS prod_cats, c.subcategoria,
  c.natureza, c.problema_canonico, c.descoberta_feature, c.palavras_evidencia, c.resumo,
  c.macrotema = p.prod_macrotema AS ok_macrotema,
  c.tipo = p.prod_tipo AS ok_tipo,
  c.sentimento = p.prod_sentimento AS ok_sentimento,
  ARRAY_TO_STRING(ARRAY(SELECT TRIM(x) FROM UNNEST(SPLIT(c.subcategoria, '|')) x ORDER BY 1), '|')
    = ARRAY_TO_STRING(ARRAY(SELECT x FROM UNNEST(p.prod_cats) x ORDER BY 1), '|') AS ok_cats_exato,
  EXISTS (SELECT 1 FROM UNNEST(SPLIT(c.subcategoria, '|')) x JOIN UNNEST(p.prod_cats) y ON TRIM(x) = y) AS ok_cats_alguma,
  -- categoria valida = linha exata da lista do prompt (a linha pode vir seguida de ": descricao")
  (SELECT LOGICAL_AND(EXISTS (
      SELECT 1 FROM UNNEST(SPLIT(SUBSTR(p.fp, STRPOS(p.fp, '<SUBCATEGORIA>') + 14,
             STRPOS(p.fp, '</SUBCATEGORIA>') - STRPOS(p.fp, '<SUBCATEGORIA>') - 14), '\n')) l
      WHERE TRIM(l) = TRIM(x) OR STARTS_WITH(TRIM(l), TRIM(x) || ':')))
   FROM UNNEST(SPLIT(c.subcategoria, '|')) x WHERE TRIM(x) != '') AS cats_validas
FROM campos c JOIN prod p USING (id_ferramenta);

-- 1) Diagnostico das falhas: quantas chamadas deram erro, truncaram (MAX_TOKENS) ou voltaram sem JSON valido
SELECT chamada, IFNULL(NULLIF(llm_status, ''), 'ok') AS status_api, finish_reason, json_valido, COUNT(*) AS chamadas,
  ROUND(AVG(len_resposta)) AS len_media_resposta
FROM resultado GROUP BY 1, 2, 3, 4 ORDER BY 1, chamadas DESC;

-- 2) Concordancia com o gravado, so chamada A. Denominador explicito:
--    pct_todos = acertos / 33 tickets (falha conta como erro); pct_validos = acertos / tickets com JSON valido
SELECT chamada, grupo, COUNT(*) AS tickets, COUNTIF(json_valido) AS n_validos,
  ROUND(SAFE_DIVIDE(COUNTIF(ok_tipo), COUNT(*)), 2) AS tipo_todos,
  ROUND(SAFE_DIVIDE(COUNTIF(ok_tipo), COUNTIF(json_valido)), 2) AS tipo_validos,
  ROUND(SAFE_DIVIDE(COUNTIF(ok_sentimento), COUNT(*)), 2) AS sentimento_todos,
  ROUND(SAFE_DIVIDE(COUNTIF(ok_sentimento), COUNTIF(json_valido)), 2) AS sentimento_validos,
  ROUND(SAFE_DIVIDE(COUNTIF(ok_cats_exato), COUNT(*)), 2) AS cats_exato_todos,
  ROUND(SAFE_DIVIDE(COUNTIF(ok_cats_exato), COUNTIF(json_valido)), 2) AS cats_exato_validos,
  ROUND(SAFE_DIVIDE(COUNTIF(cats_validas), COUNTIF(json_valido)), 2) AS cats_validas_validos
FROM resultado WHERE chamada LIKE 'A%' GROUP BY 1, 2 ORDER BY 1, 2;

-- 3) Autoconsistencia: A_rep1 x A_rep2 no mesmo ticket (so tickets em que as duas voltaram validas)
SELECT COUNT(*) AS tickets_comparaveis,
  COUNTIF(a.tipo = b.tipo) AS tipo_igual, COUNTIF(a.sentimento = b.sentimento) AS sentimento_igual,
  COUNTIF(a.subcategoria = b.subcategoria) AS cats_igual, COUNTIF(a.macrotema = b.macrotema) AS macro_igual
FROM resultado a JOIN resultado b USING (id_ferramenta)
WHERE a.chamada = 'A_rep1' AND b.chamada = 'A_rep2' AND a.json_valido AND b.json_valido;

-- 4) problema_canonico da chamada B: os tickets do mesmo problema devem cair em poucos textos
SELECT problema_canonico, natureza, COUNT(*) AS tickets, STRING_AGG(id_ferramenta, ', ' ORDER BY id_ferramenta) AS ids
FROM resultado WHERE chamada = 'B' AND json_valido AND IFNULL(problema_canonico, '') != ''
GROUP BY 1, 2 ORDER BY tickets DESC;

-- 5) Detalhe linha a linha (inclui as falhas, para abrir o texto cru depois)
SELECT * FROM resultado ORDER BY grupo, id_ferramenta, chamada;
