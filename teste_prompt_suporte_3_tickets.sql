-- Teste do prompt "alternativa Gemini" (regras do Suporte V2 importadas) em 3 tickets reais.
-- Tickets: 6189021 (boleto pago nao baixado), 6178426 (Pix de boleto nao baixado), 6188174 (boleto Sicoob).
-- 3 repeticoes por ticket para medir a estabilidade do problema_canonico (texto livre).
--
-- ANTES DE RODAR:
--  * Precisa de permissao para AI.GENERATE (Vertex AI User para o seu usuario) OU de uma conexao
--    BigQuery -> Vertex AI na regiao US. Se for usar conexao, descomente a linha connection_id
--    e troque pelo seu ID: 'PROJETO.US.NOME_DA_CONEXAO'.
--  * Ajuste o endpoint para o mesmo modelo do pipeline de producao (aqui: gemini-3.1-flash-lite).
--  * A lista de categorias e a ATUAL (272), filtrada por metadado (Cobranca, Financeiro, Conta PJ,
--    Conciliacao, Pagamento, Atendimento por bot). A lista de 177 (Taxonomia v1) nao esta disponivel.
--  * O filtro de particao em nk_event_date e obrigatorio: sem ele a query varre ~35 GB.
--  * A coluna evidencia vem como contagem de palavras (pode conter trecho literal do cliente).

WITH src AS (
  SELECT id_ferramenta, full_prompt AS fp
  FROM `contaazul-ssbi.gold_strategy.dim_voc_full_category`
  WHERE source = 'zendesk' AND llm_send_status = 'enviado_llm'
    AND nk_event_date >= DATETIME('2026-10-16') AND nk_event_date < DATETIME('2026-10-20')
    AND id_ferramenta IN ('6189021', '6188174', '6178426')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_ferramenta ORDER BY id_ferramenta) = 1
), cats AS (
  SELECT id_ferramenta, STRING_AGG(line, '\n' ORDER BY line) AS shortlist
  FROM src, UNNEST(SPLIT(SUBSTR(fp, STRPOS(fp, '<SUBCATEGORIA>') + 14,
       STRPOS(fp, '</SUBCATEGORIA>') - STRPOS(fp, '<SUBCATEGORIA>') - 14), '\n')) AS line
  WHERE REGEXP_CONTAINS(line, r'^(Cobrança|Financeiro|Conta PJ|Extrato/Conciliação/Integração|Forma / Condições de Pagamento|Forma de Pagamento:|Templates de configurações da cobrança|Faturamento do Plano|Experiência IA:|Resolução:|Transbordo:|Canal Virtual/Geral:|Solução repetitiva:|Geral:|Suporte Geral:)')
  GROUP BY id_ferramenta
), prompts AS (
  SELECT s.id_ferramenta, rep,
    CONCAT(
"""PAPEL: Você é um especialista em Voice of Customer de um ERP SaaS.
TAREFA: Para o atendimento abaixo, extraia os campos pedidos seguindo as regras.

<NATUREZA>
Escolha UM valor para o tipo de trabalho que o pedido exige do time:
bug: funciona errado, parou de funcionar, dá erro ou o resultado diverge do esperado.
usabilidade: a funcionalidade existe e resolve, mas o cliente não a encontra ou o caminho é caro. Pergunta de onde fica um recurso que existe é usabilidade, não dúvida.
gap: não existe no produto, ou existe e não cobre o caso (limite, campo, regra). Pergunta de como fazer algo que o produto não faz é gap.
dúvida: pergunta conceitual, de regra de negócio ou de legislação, não sobre onde clicar.
infra: acesso, login, indisponibilidade, lentidão generalizada. Não consegue acessar é infra.
comercial: preço, plano, contrato, cobrança da assinatura, cancelamento.
operacional: o cliente cobra status ou prazo do próprio chamado. Não é sinal de produto.
ruído: saudação, teste, abandono, nada classificável.
Se o texto trouxer mais de uma natureza, vale a que gera trabalho de engenharia, nesta ordem: bug, infra, usabilidade, gap.
</NATUREZA>

<POSTURA>
Como o cliente se expressou: dúvida, reclamação, sugestão, elogio ou indeterminado. É independente da natureza: um bug relatado com raiva tem natureza bug e postura reclamação.
</POSTURA>

<GRAO>
Em bug, gap e usabilidade, problema_canonico deve ser o problema específico na linguagem do cliente, não o assunto geral.
Se o cliente pergunta como faço, onde acho ou é possível, sem relatar defeito, preencha descoberta_feature com a funcionalidade que ele tenta alcançar, em vez de descrever a pergunta.
</GRAO>

<ENTRADA>
No texto do atendimento, as mensagens do cliente trazem o motivo do contato. Mensagens de bot e de atendente são contexto de resolução: use para entender o desfecho, nunca como motivo.
</ENTRADA>

<REGRAS>
- categoria: use somente nomes da lista CATEGORIAS, exatamente como escritos (sem a descrição após os dois pontos). Se nenhuma se encaixar, retorne curadoria true e categoria vazia. Nunca invente rótulo.
- sentimento: um de Satisfação, Confiança, Gratidão, Alegria, Confusão / dúvida, Desinteresse, Insegurança, Insatisfação, Raiva, Decepção, Não é possível determinar.
- evidencia: trecho literal de até 15 palavras do cliente, sem nome, CPF, CNPJ, e-mail ou telefone.
- resumo: uma frase.
</REGRAS>

<CATEGORIAS>
""", c.shortlist, "\n</CATEGORIAS>\n\n", SUBSTR(s.fp, STRPOS(s.fp, '<CNTX>'))) AS prompt
  FROM src s JOIN cats c USING (id_ferramenta), UNNEST(GENERATE_ARRAY(1, 3)) AS rep
)
SELECT id_ferramenta, rep, LENGTH(prompt) AS len_prompt,
  r.natureza, r.postura, r.sentimento, r.categoria, r.problema_canonico, r.descoberta_feature, r.curadoria,
  ARRAY_LENGTH(SPLIT(r.evidencia, ' ')) AS palavras_evidencia, r.resumo, r.status AS status_llm
FROM (
  SELECT id_ferramenta, rep, prompt,
    AI.GENERATE(
      prompt,
      connection_id => 'us.vertex_connection',
      endpoint => 'gemini-2.5-flash-lite',
      model_params => JSON '{"labels":{"ca_initiative":"voc_v0","ca_application_name":"bigquery"},"generation_config":{"thinking_config":{"thinking_budget":0},"temperature":0.0,"maxOutputTokens":2000}}',
      output_schema => 'natureza STRING, postura STRING, sentimento STRING, categoria STRING, problema_canonico STRING, descoberta_feature STRING, curadoria BOOL, evidencia STRING, resumo STRING'
    ) AS r
  FROM prompts
)
ORDER BY id_ferramenta, rep;