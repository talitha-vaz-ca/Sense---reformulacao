-- Teste comparativo: prompt de PRODUCAO (Sense 2.0) x prompt de producao + campos novos, em 33 tickets Zendesk.
--
-- Duas variantes por ticket, mesma chamada AI.GENERATE:
--   replay  = full_prompt gravado na dim_voc_full_category, SEM alteracao (lista completa de ~273 categorias,
--             multi-rotulo, definicoes de macrotema/tipo/sentimento de producao). Mede se o proprio modelo reproduz
--             o que esta gravado. Qualquer diferenca aqui NAO vem do prompt novo (modelo, temperatura, nao-determinismo).
--   hibrido = o mesmo full_prompt + bloco NOVOS_CAMPOS inserido antes de "Antes de responder". Categoria, tipo e
--             sentimento continuam sob as regras de producao; natureza/problema_canonico/descoberta_feature vem por cima.
--
-- Amostra (ids fixos para o teste ser reproduzivel; todos em nk_event_date de 2026-10-16 a 2026-10-27):
--   O  (3)  tickets do primeiro teste
--   A  (12) tema "boleto/Pix pago e nao baixado" por regex no resumo. Sao 7 acertos reais e 5 falsos positivos
--           (6212390, 6191974, 6182188, 6191979, 6206529). Os falsos servem de controle: o problema_canonico deles
--           NAO pode cair no mesmo texto dos acertos.
--   B  (18) 3 tickets por tipo de incidente (Duvida, Incidentes, Reclamacao, Ajustes, Sugestao, Elogio), fora do tema A
--
-- ANTES DE RODAR:
--   * Filtro de particao em nk_event_date e obrigatorio (~430 MB com full_prompt; sem filtro varre ~35 GB).
--   * Producao usa gemini-3.1-flash-lite via endpoint global. Se o seu connection_id nao alcanca esse modelo,
--     troque model_endpoint pelo 'gemini-2.5-flash-lite' e registre isso: a comparacao passa a incluir diferenca de modelo.
--   * Custo de LLM: 33 tickets x 2 variantes x ~9 mil tokens de entrada, centavos.

DECLARE model_endpoint STRING DEFAULT 'gemini-3.1-flash-lite';
-- Alternativa com URL completa, como na producao (troque o projeto pelo do seu dev):
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
), prompts AS (
  SELECT id_ferramenta, grupo, 'replay' AS variante, fp AS prompt FROM prod
  UNION ALL
  SELECT id_ferramenta, grupo, 'hibrido',
    REPLACE(fp, 'Antes de responder, valide', """<NOVOS_CAMPOS>
Além dos campos acima, retorne também:
- natureza: UM valor para o tipo de trabalho que o pedido exige do time.
  bug: funciona errado, parou de funcionar, dá erro ou o resultado diverge do esperado.
  usabilidade: a funcionalidade existe e resolve, mas o cliente não a encontra ou o caminho é caro.
  gap: não existe no produto, ou existe e não cobre o caso (limite, campo, regra).
  dúvida: pergunta conceitual ou de regra de negócio. Se o produto se comporta como foi desenhado e o cliente só não conhecia a regra, é dúvida, não bug.
  infra: acesso, login, indisponibilidade, lentidão generalizada.
  comercial: preço, plano, contrato, cobrança da assinatura, cancelamento.
  operacional: o cliente cobra status ou prazo do próprio chamado.
  ruído: saudação, teste, abandono, nada classificável.
  Se houver mais de uma natureza, vale a que gera trabalho de engenharia, nesta ordem: bug, infra, usabilidade, gap.
- problema_canonico: em bug, gap e usabilidade, o problema específico na linguagem do cliente, em uma frase, sem número de venda, valor ou nome. Nos demais casos, vazio.
- descoberta_feature: preencha SOMENTE se o cliente pergunta como fazer, onde achar ou se é possível, sem relatar defeito. Em bug, deixe vazio.
- evidencia: trecho literal de até 15 palavras de uma mensagem do CLIENTE, sem nome, CPF, CNPJ, e-mail ou telefone.
Mensagens de bot e de atendente são contexto de resolução, nunca o motivo do contato.
</NOVOS_CAMPOS>

Antes de responder, valide""")
  FROM prod
), gerado AS (
  SELECT id_ferramenta, grupo, variante,
    AI.GENERATE(
      prompt,
      connection_id => 'us.vertex_connection',
      endpoint => model_endpoint,
      model_params => JSON '{"labels":{"ca_initiative":"voc_v0","ca_application_name":"bigquery"},"generation_config":{"thinking_config":{"thinking_budget":0},"temperature":0.0,"maxOutputTokens":2000}}',
      output_schema => 'macrotema STRING, tipo_de_incidente_gemini STRING, sentimento STRING, subcategoria STRING, resumo_do_incidente_gemini STRING, natureza STRING, problema_canonico STRING, descoberta_feature STRING, evidencia STRING'
    ) AS r
  FROM prompts
)
SELECT g.id_ferramenta, g.grupo, g.variante,
  p.prod_macrotema, g.r.macrotema AS novo_macrotema,
  p.prod_tipo, g.r.tipo_de_incidente_gemini AS novo_tipo,
  p.prod_sentimento, g.r.sentimento AS novo_sentimento,
  ARRAY_TO_STRING(p.prod_cats, ' | ') AS prod_cats,
  g.r.subcategoria AS novo_cats,
  g.r.natureza, g.r.problema_canonico, g.r.descoberta_feature,
  ARRAY_LENGTH(SPLIT(g.r.evidencia, ' ')) AS palavras_evidencia,
  g.r.resumo_do_incidente_gemini AS novo_resumo,
  g.r.status AS status_llm,
  -- comparacao com o gravado em producao
  g.r.macrotema = p.prod_macrotema AS ok_macrotema,
  g.r.tipo_de_incidente_gemini = p.prod_tipo AS ok_tipo,
  g.r.sentimento = p.prod_sentimento AS ok_sentimento,
  -- conjunto de categorias identico (ordem ignorada)
  (SELECT ARRAY_TO_STRING(ARRAY(SELECT TRIM(x) FROM UNNEST(SPLIT(g.r.subcategoria, '|')) x ORDER BY 1), '|'))
    = ARRAY_TO_STRING(ARRAY(SELECT x FROM UNNEST(p.prod_cats) x ORDER BY 1), '|') AS ok_cats_exato,
  -- ao menos uma categoria em comum
  EXISTS (SELECT 1 FROM UNNEST(SPLIT(g.r.subcategoria, '|')) x JOIN UNNEST(p.prod_cats) y ON TRIM(x) = y) AS ok_cats_alguma,
  -- toda categoria devolvida existe no vocabulario de producao? (aprox.: aparece em full_prompt)
  (SELECT LOGICAL_AND(STRPOS(p.fp, TRIM(x)) > 0) FROM UNNEST(SPLIT(g.r.subcategoria, '|')) x WHERE TRIM(x) != '') AS cats_validas
FROM gerado g JOIN prod p USING (id_ferramenta);

-- 1) Resumo: taxa de concordancia com a producao, por variante e grupo
SELECT variante, grupo, COUNT(*) AS tickets,
  ROUND(AVG(CAST(ok_macrotema AS INT64)), 2) AS pct_macrotema,
  ROUND(AVG(CAST(ok_tipo AS INT64)), 2) AS pct_tipo,
  ROUND(AVG(CAST(ok_sentimento AS INT64)), 2) AS pct_sentimento,
  ROUND(AVG(CAST(ok_cats_exato AS INT64)), 2) AS pct_cats_exato,
  ROUND(AVG(CAST(ok_cats_alguma AS INT64)), 2) AS pct_cats_alguma,
  ROUND(AVG(CAST(cats_validas AS INT64)), 2) AS pct_cats_validas
FROM resultado GROUP BY 1, 2 ORDER BY 1, 2;

-- 2) Detalhe linha a linha
SELECT * FROM resultado ORDER BY grupo, id_ferramenta, variante;

-- 3) Estabilidade do problema_canonico entre tickets: os 7 acertos do grupo A devem agrupar em poucos textos
--    e os 5 falsos positivos nao podem entrar nesse grupo.
SELECT problema_canonico, natureza, COUNT(*) AS tickets, STRING_AGG(id_ferramenta, ', ' ORDER BY id_ferramenta) AS ids
FROM resultado WHERE variante = 'hibrido' AND grupo IN ('A', 'O') AND problema_canonico IS NOT NULL AND problema_canonico != ''
GROUP BY 1, 2 ORDER BY tickets DESC;
