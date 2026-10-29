-- Simulacao de um dia completo (segunda 19/10/2026): Sense 2.0 (agente de Suporte V2) x populacao inteira de tickets com A + B.
--
-- COMO RODAR: console do BigQuery, projeto contaazul-datalake-dev, como UM script (executar tudo).
-- Cria 4 tabelas temporarias (expiram em 7 dias) em contaazul-datalake-dev.dataform. Troque o dataset se voce nao tiver
-- permissao de escrita nele. Depois do script ha 6 consultas de resultado.
--
-- O que cada tabela guarda:
--   tmp_sim_suporte_20261019_pop  Os tickets Zendesk do dia, com a classificacao GRAVADA hoje no Sense 2.0 (chamada A, nao e
--                                 refeita), a ponte ticket -> conversa Intercom e o contexto do ticket (<CNTX>) para a chamada B.
--   tmp_sim_suporte_20261019_b    Chamada B (natureza, problema_canonico, descoberta_feature, evidencia) para todos os tickets.
--   tmp_sim_suporte_20261019_map  Mapa categoria -> domain/subdomain derivado da copia do Erick no dev
--                                 (gold_strategy_dev_ericklemos.dim_voc_full_category, que ja tem as 3 colunas novas).
--
-- Custo de LLM: so a chamada B, 1.215 tickets, cerca de US$ 0,55 (estimativa a 4 chars/token e US$ 0,25 / US$ 1,50 por milhao).
-- Nada aqui altera dim_voc_full_category nem tabela de producao.
--
-- AVISO: a parte de ponte/populacao usa consultas validadas no projeto contaazul-ssbi. A parte do dev (mapa do Erick e
-- AI.GENERATE) NAO foi executada por mim (o MCP nao tem acesso ao dev). Se der erro de coluna na copia do Erick, confira os
-- nomes com INFORMATION_SCHEMA.COLUMNS (a investigacao de 27/10 lista domain, subdomain e is_atendimento).

DECLARE dia_ini DATETIME DEFAULT DATETIME('2026-10-19');
DECLARE dia_fim DATETIME DEFAULT DATETIME('2026-10-20');
DECLARE model_endpoint STRING DEFAULT 'gemini-3.1-flash-lite';

-- 1) Populacao do dia: A gravado + ponte com o Intercom + contexto para a chamada B
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_pop`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH tk AS (
  SELECT CAST(id_ferramenta AS INT64) AS ticket_id,
    ANY_VALUE(ticket_type) AS ticket_type,
    ANY_VALUE(macro_theme) AS macrotema,
    ANY_VALUE(incident_type_gemini) AS tipo_incidente,
    ANY_VALUE(sentiment) AS sentimento,
    ARRAY_AGG(DISTINCT category_gemini IGNORE NULLS) AS categorias,
    ANY_VALUE(transcription IS NOT NULL) AS tem_transcricao,
    ANY_VALUE(SUBSTR(full_prompt, STRPOS(full_prompt, '<CNTX>'))) AS cntx
  FROM `contaazul-ssbi.gold_strategy.dim_voc_full_category`
  WHERE source = 'zendesk' AND llm_send_status = 'enviado_llm'
    AND nk_event_date >= dia_ini AND nk_event_date < dia_fim
  GROUP BY 1
), cm AS (
  SELECT ticket_id, ANY_VALUE(intercom_conversation_id) AS intercom_conversation_id, ANY_VALUE(source) AS origem_conversa
  FROM `contaazul-ssbi.silver_serve.zendesk_concatened_messages`
  WHERE created_at >= DATETIME_SUB(dia_ini, INTERVAL 7 DAY) AND ticket_id IS NOT NULL
  GROUP BY 1
), ic AS (
  SELECT CAST(intercom_conversation_id AS STRING) AS icid, ANY_VALUE(interaction_type) AS interaction_type,
    LOGICAL_OR(ai_issue_summary IS NOT NULL AND LENGTH(TRIM(ai_issue_summary)) > 0) AS tem_resumo_ia
  FROM `contaazul-ssbi.silver_serve.ingestion_intercom_conversations`
  WHERE updated_at >= DATETIME_SUB(dia_ini, INTERVAL 7 DAY)
  GROUP BY 1
)
SELECT tk.*, cm.origem_conversa, cm.intercom_conversation_id IS NOT NULL AS veio_do_intercom,
  ic.interaction_type, ic.tem_resumo_ia
FROM tk LEFT JOIN cm USING (ticket_id) LEFT JOIN ic ON ic.icid = cm.intercom_conversation_id;

-- 2) Chamada B em todos os tickets do dia (mesmo prompt B da v2 do teste de 33 tickets)
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_b`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH gerado AS (
  SELECT ticket_id,
    AI.GENERATE(
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
""", cntx),
      connection_id => 'us.vertex_connection',
      endpoint => model_endpoint,
      model_params => JSON '{"labels":{"ca_initiative":"voc_v0","ca_application_name":"bigquery"},"generation_config":{"thinking_config":{"thinking_budget":0},"temperature":0.0,"maxOutputTokens":2000,"responseMimeType":"application/json"}}'
    ) AS r
  FROM `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_pop`
), lido AS (
  SELECT ticket_id, r.status AS llm_status, COALESCE(REGEXP_EXTRACT(r.result, r'(?s)\{.*\}'), r.result) AS json_str FROM gerado
)
SELECT ticket_id, llm_status, SAFE.PARSE_JSON(json_str) IS NOT NULL AS json_valido,
  JSON_VALUE(json_str, '$.natureza') AS natureza,
  JSON_VALUE(json_str, '$.problema_canonico') AS problema_canonico,
  JSON_VALUE(json_str, '$.descoberta_feature') AS descoberta_feature,
  ARRAY_LENGTH(SPLIT(JSON_VALUE(json_str, '$.evidencia'), ' ')) AS palavras_evidencia
FROM lido;

-- 3) Mapa categoria -> domain/subdomain, a partir da copia do Erick (itens do Zendesk com UMA so categoria,
--    para que o dominio do item seja atribuivel a essa categoria). Pode vir com '|' (dominio composto): ver R3.
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_map`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH erick AS (
  SELECT id_ferramenta, category_gemini, domain, subdomain
  FROM `contaazul-datalake-dev.gold_strategy_dev_ericklemos.dim_voc_full_category`
  WHERE source = 'zendesk'
), unicos AS (
  SELECT id_ferramenta FROM erick GROUP BY 1 HAVING COUNT(*) = 1
)
SELECT e.category_gemini, e.domain, e.subdomain, COUNT(*) AS itens_unicos
FROM erick e JOIN unicos USING (id_ferramenta)
GROUP BY 1, 2, 3
QUALIFY ROW_NUMBER() OVER (PARTITION BY e.category_gemini ORDER BY COUNT(*) DESC) = 1;

-- ===================== RESULTADOS =====================

-- R1) Cobertura: Sense 2.0 (Suporte V2, numeros do log de 20/10 no Notion) x populacao inteira do dia
WITH v2 AS (
  SELECT 2728 AS universo_conversas, 934 AS selecionadas, 102 AS censo_n2_n3, 38 AS censo_muito_negativo,
         794 AS amostra_30pct, 229 AS prefiltradas_vazias, 705 AS classificadas, 130 AS sinais_ativos, 114 AS abaixo_do_piso
)
SELECT 'Sense 2.0 (Suporte V2) - conversas Intercom' AS lado, universo_conversas AS universo, classificadas AS observados_um_a_um,
  ROUND(classificadas / universo_conversas, 3) AS pct_observado, censo_n2_n3 AS n2_n3_observados
FROM v2
UNION ALL
SELECT 'A + B - tickets Zendesk', COUNT(*), COUNTIF(tem_transcricao), ROUND(COUNTIF(tem_transcricao) / COUNT(*), 3),
  COUNTIF(ticket_type IN ('Ajustes', 'Incidente'))
FROM `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_pop`;

-- R2) Ponte: de onde vem o ticket (Intercom x web/e-mail x sem conversa) e quanto e N2/N3
SELECT IFNULL(origem_conversa, '(sem linha na concatenada)') AS origem, veio_do_intercom, IFNULL(interaction_type, '(n/a)') AS interaction_type,
  COUNT(*) AS tickets, COUNTIF(ticket_type IN ('Ajustes', 'Incidente')) AS n2_n3, COUNTIF(tem_transcricao) AS com_transcricao
FROM `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_pop`
GROUP BY 1, 2, 3 ORDER BY tickets DESC;

-- R3) Dominio/subdominio simulados (mapa do Erick): cobertura do mapa, dominios compostos e distribuicao
WITH t AS (
  SELECT p.ticket_id, c AS categoria, m.domain, m.subdomain
  FROM `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_pop` p, UNNEST(p.categorias) AS c
  LEFT JOIN `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_map` m ON m.category_gemini = c
)
SELECT 'categorias-ticket sem dominio no mapa' AS metrica, CAST(COUNTIF(domain IS NULL) AS STRING) AS valor, COUNT(*) AS base FROM t
UNION ALL SELECT 'categorias-ticket com dominio composto (|)', CAST(COUNTIF(domain LIKE '%|%') AS STRING), COUNT(*) FROM t
UNION ALL SELECT CONCAT('dominio: ', IFNULL(domain, '(sem dominio)')), CAST(COUNT(DISTINCT ticket_id) AS STRING), COUNT(*) FROM t GROUP BY domain
ORDER BY 1;

-- R4) is_atendimento: como esta no dev (true em todo Zendesk) x proxy por categoria de atendimento x natureza da chamada B
WITH x AS (
  SELECT p.ticket_id,
    EXISTS (SELECT 1 FROM UNNEST(p.categorias) c WHERE c IN ('Transbordo', 'Tempo de atendimento/espera', 'Suporte Geral', 'Chat', 'Telefonico', 'Geral')) AS atend_proxy,
    b.natureza
  FROM `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_pop` p JOIN `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_b` b USING (ticket_id)
)
SELECT 'is_atendimento = true (regra do dev)' AS definicao, COUNT(*) AS tickets FROM x
UNION ALL SELECT 'proxy: tem categoria de atendimento', COUNTIF(atend_proxy) FROM x
UNION ALL SELECT 'chamada B: natureza operacional ou ruido', COUNTIF(natureza IN ('operacional', 'ruído', 'ruido')) FROM x
UNION ALL SELECT 'concordam (proxy e natureza operacional/ruido)', COUNTIF(atend_proxy AND natureza IN ('operacional', 'ruído', 'ruido')) FROM x;

-- R5) Enriquecimento da B: natureza por origem e por nivel (N1/N2/N3) do ticket
SELECT IF(p.veio_do_intercom, 'intercom', 'fora do intercom') AS origem, p.ticket_type, b.natureza, COUNT(*) AS tickets,
  COUNTIF(IFNULL(b.problema_canonico, '') != '') AS com_problema_canonico,
  COUNTIF(IFNULL(b.descoberta_feature, '') != '') AS com_descoberta_feature,
  COUNTIF(NOT b.json_valido) AS json_invalido
FROM `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_pop` p JOIN `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_b` b USING (ticket_id)
GROUP BY 1, 2, 3 ORDER BY origem, p.ticket_type, tickets DESC;

-- R6) Natureza x dominio (o corte que o Sense 2.0 so tem por cluster, aqui por ticket) e problema_canonico mais frequente
WITH t AS (
  SELECT p.ticket_id, ANY_VALUE(m.domain) AS dominio, ANY_VALUE(b.natureza) AS natureza, ANY_VALUE(b.problema_canonico) AS problema
  FROM `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_pop` p
  JOIN `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_b` b USING (ticket_id)
  LEFT JOIN `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_map` m ON m.category_gemini = p.categorias[SAFE_OFFSET(0)]
  GROUP BY 1
)
SELECT IFNULL(dominio, '(sem dominio)') AS dominio, natureza, COUNT(*) AS tickets,
  COUNT(DISTINCT problema) AS textos_distintos_de_problema,
  ARRAY_AGG(problema IGNORE NULLS ORDER BY LENGTH(problema) LIMIT 1)[SAFE_OFFSET(0)] AS exemplo_de_problema
FROM t GROUP BY 1, 2 ORDER BY tickets DESC LIMIT 60;
