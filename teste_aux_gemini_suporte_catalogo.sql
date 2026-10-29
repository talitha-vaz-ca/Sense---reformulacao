-- =====================================================================================================
-- TESTE AUX-S: Gemini 3.1 flash-lite como LLM auxiliar ANTES do agente Suporte V2 (controle do plano de testes)
-- Dia 19/10/2026. Compara o que o Gemini consegue fazer sozinho (extrair campos e casar com o catalogo de sinais)
-- com o resultado REAL da V2 prod no mesmo dia (Mencoes por sinal na DB de Sinais do Notion, ponto [diario] 2026-10-19).
--
-- COMO RODAR (console do BigQuery, projeto contaazul-datalake-dev; o MCP nao tem acesso ao dev nem ao AI.GENERATE):
--   1) Rode o script ate o fim das secoes 1 a 4 (cria 4 tabelas temporarias, expiram em 7 dias).
--   2) Rode as consultas R1..R8 (secao 5) UMA POR VEZ e cole os resultados na conversa.
-- Custo estimado: ~US$ 1 por repeticao (705 chamadas P2 com catalogo de 146 nomes + 705 chamadas P1). Nenhuma tabela de prod e alterada.
--
-- O QUE ESTE TESTE PROVA E O QUE NAO PROVA
--   Prova: se o Gemini reproduz o RANKING de sinais do dia que o Claude (V2) produziu, a um custo de dados desprezivel.
--   Nao prova: acerto por conversa. A V2 nao persiste conversa->sinal (zero-storage), entao nao ha verdade por item.
--   A verdade usada e por SINAL (Mencoes escaladas da V2 em 19/10). A amostra R8 e o ponto de partida do conjunto rotulado.
-- LIMITES CONHECIDOS
--   - Catalogo reduzido: 146 de 273 sinais (os 100 de maior Mencoes em 19/10 + 46 de maior Score que nao estao entre eles).
--     Os ~120 sinais restantes (cauda) nao estao na lista: o Gemini tende a marca-los como "sem match".
--   - A selecao da V2 e reproduzida por SQL (censo N2/N3 + censo 'Muito negativo' + amostra 30% por hash). Em 19/10 ela da ~705,
--     coerente com o que foi medido antes. O pre-filtro de ruido e so ai_issue_summary vazio, como na V2.
--   - Os pesos sao os da V2: censo x1, amostra x(1/0,30). O piso >=3 conversas cruas da V2 nao e aplicado aqui.
-- =====================================================================================================

DECLARE dia_ini DATETIME DEFAULT DATETIME('2026-10-19');
--DECLARE model_endpoint STRING DEFAULT 'gemini-3.1-flash-lite';
DECLARE taxa_d INT64 DEFAULT 10;   -- taxa K/D da V2 (30% = 3/10)
DECLARE taxa_k INT64 DEFAULT 3;
DECLARE n_reps INT64 DEFAULT 1;    -- use 2 para medir autoconsistencia (R6)
DECLARE catalogo_txt STRING;

-- ----------------------------------------------------------------------------------------------------
-- 1) Populacao: reproduz a SELECAO da V2 (100% metadado)
-- ----------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_suporte_pop`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH c AS (
  SELECT CAST(intercom_conversation_id AS STRING) AS cid, sentiment, fin_ai_agent_resolution_state AS res_state,
    ai_issue_summary AS resumo
  FROM `contaazul-ssbi.silver_serve.ingestion_intercom_conversations`
  WHERE DATE(created_at) = DATE(dia_ini)
), tk AS (
  -- guard de fan-out da V2: 1 linha por conversa, ordenacao deterministica (N3 > N2 > N1, recencia, id)
  SELECT CAST(intercom_conversation_id AS STRING) AS cid, ticket_level
  FROM `contaazul-ssbi.gold_serve.dim_zendesk_tickets_detailed`
  WHERE intercom_conversation_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY intercom_conversation_id
    ORDER BY CASE ticket_level WHEN 'N3' THEN 3 WHEN 'N2' THEN 2 WHEN 'N1' THEN 1 ELSE 0 END DESC,
             nk_date DESC NULLS LAST, id DESC) = 1
), j AS (
  SELECT c.*, tk.ticket_level,
    IFNULL(tk.ticket_level IN ('N2', 'N3'), FALSE) AS censo_n2n3,
    (c.resumo IS NULL OR TRIM(c.resumo) = '') AS sem_resumo
  FROM c LEFT JOIN tk USING (cid)
)
SELECT cid, resumo, sentiment, res_state, ticket_level,
  CASE WHEN censo_n2n3 THEN 'censo_n2n3' WHEN sentiment = 'Muito negativo' THEN 'censo_negativo' ELSE 'amostra' END AS balde,
  IF(censo_n2n3 OR sentiment = 'Muito negativo', 1.0, taxa_d / taxa_k) AS peso
FROM j
WHERE NOT sem_resumo
  AND (censo_n2n3 OR sentiment = 'Muito negativo' OR MOD(MOD(FARM_FINGERPRINT(cid), taxa_d) + taxa_d, taxa_d) < taxa_k);

-- ----------------------------------------------------------------------------------------------------
-- 2) Catalogo (lista fechada) + verdade da V2 por sinal em 19/10
--    Formato por linha: nome || mencoes_v2_20261019 (vazio = sinal do catalogo sem ponto relevante em 19/10)
--    Fonte: DB Sinais Suporte V2 prod (Notion, ds e7ab0182...), leitura em 29/10/2026.
--    Para o teste completo, substitua pelo export dos 273 sinais (nome || valor do ponto [diario] de 2026-10-19).
-- ----------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_suporte_cat`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH raw AS (
  SELECT linha FROM UNNEST(SPLIT(r'''
Aumento/reajuste do valor da renovação do plano percebido como excessivo || 96
Erro genérico na emissão de nota fiscal (sem detalhe) || 64
Cancelamento de plano/assinatura por decisão do cliente (conta própria) || 60.6667
Negociação de valor/desconto na renovação do plano || 56.3333
Divergência de saldo na conciliação bancária || 55.3333
Dúvida genérica sobre como funciona a renovação do plano || 43.3333
Descoberta: informações gerais sobre a CA Pro (pré-venda) || 40
Nota fiscal de devolução: dúvida de preenchimento (IPI/ICMS/DIFAL) e vínculo com a nota original || 40
Status/prazo do chamado || 34
Descoberta: gerar relatório personalizado (Excel/DRE/centro de custo) || 33.3333
Erro/dúvida na retenção de impostos (ISS/PIS/COFINS) na nota fiscal || 30.6667
Descoberta: lançar transferência entre contas, fatura de cartão e pagamento parcial || 30
Cancelamento/reativação de licença || 26.6667
Descoberta: integração via API pública || 23.3333
Reenquadramento automático migra plano para faixa de faturamento divergente do esperado || 23.3333
Insatisfação com qualidade/demora do atendimento de suporte || 22
Erro no código/classificação tributária do serviço (CNAE, código de serviço, ISS) || 21
MFA/2FA: reset e recuperação de acesso || 20
Descoberta: adesão/prazo do Emissor Nacional (NFS-e padrão nacional) para o município || 20
QR Code para configurar autenticador (2FA) não aparece corretamente || 20
Descoberta: estoque (ajuste, baixa, relatório, kits) || 20
Descoberta: configurar boleto bancário (banco, Pix, código da empresa) || 20
Lançamentos bancários não aparecem/somem na conciliação após importação || 19.6667
Renovação/cobrança automática do plano sem autorização percebida pelo cliente || 17.6667
Descoberta: canal, horário e contato do suporte || 17.6667
Erro E160 (carga tributária aproximada obrigatória) trava emissão de NFS-e || 17.3333
Reset/recuperação de acesso à conta (login/senha, sem MFA) || 16.6667
Dúvida: parcelamento/forma de pagamento da renovação no cartão de crédito || 16.6667
Descoberta: obter boleto de pagamento || 16.6667
Descoberta: opções de planos com custo mais baixo || 16.6667
Descoberta: como fazer lançamentos financeiros (receita/entrada/categoria) || 16.6667
Descoberta: atualização cadastral (como fazer / opção "Atualizar agora" não aparece) || 16.6667
Descoberta: importar planilha (contas a pagar, clientes, serviços) || 16.6667
Descoberta: cadastrar cliente, vendedor e parceiro || 16.6667
Erro de validação IBS/CBS impede emissão de nota || 16.3333
Sistema lento/trava com frequência, dificultando a operação || 15.3333
E-mail de confirmação/retorno do chamado não recebido ou incorreto || 15.3333
Sistema bloqueia acesso pedindo novo plano mesmo com plano ativo pago || 14.3333
DDA: boletos cancelados ainda aparecem / dúvidas de uso do DDA || 14.3333
Descoberta/Dúvida: preparar o sistema para a reforma tributária (IBS/CBS) || 13.3333
Erro relacionado a certificado digital na emissão de nota fiscal || 13.3333
Sincronização de plano de contas/lançamentos com sistema Domínio (contador) || 13.3333
Descoberta: registrar compra de serviço / XML de compra || 13.3333
Perfis e permissões de acesso de usuário || 13.3333
Notas emitidas no Portal Nacional/prefeitura não sincronizam nem são importadas para o sistema || 12
Não consigo cancelar NF-e/NFS-e || 11
Dúvida sobre gestão/edição de contrato de venda recorrente || 11
Integração bancária instável (Santander/C6/Caixa Econômica/outros bancos) || 11
Descoberta: alterar titularidade da conta para novo CNPJ || 11
Conciliação pendente: não consegue ignorar/excluir lançamentos ou arquivo OFX importado || 11
Aprovação de transferência no CA de Bolso: opção de aprovar não aparece || 11
Descoberta: transferir/desconectar/substituir licença entre clientes || 10
Erro/instabilidade na integração bancária Open Finance/OFX (lançamentos não importados) || 10
Bloqueio de acesso mesmo após pagamento do boleto (plano) || 10
Descoberta: treinamentos ao vivo e como se inscrever || 10
Descoberta: alterar forma de pagamento da assinatura || 10
Categorias financeiras / receita de centro de custo não aparecem corretamente vinculadas no relatório DRE || 10
Desconto/valor negociado não é aplicado no sistema para pagamento || 10
Descoberta: baixar XMLs de notas (entrada/saída) para contabilidade || 10
Descoberta: consultar valor do plano atual || 10
Descoberta: fazer upgrade de licença || 10
Descoberta: cadastrar/excluir chave Pix || 10
Integração bancária com a Cora travada/instável || 10
Descoberta: consultar contrato e termos do plano || 10
Rejeição da NFS-e por tipos de retenção de PIS/COFINS/CSLL não suportados/configuráveis || 9.6667
Boleto pago pelo cliente não é baixado/creditado no sistema mesmo com comprovante || 9.6667
Backup de dados antes de cancelamento/exclusão de conta || 8.6667
Erro EM062 de correlação Serviço/NBS/Indicador de Operação/Classificação Tributária na emissão de NFS-e || 8.6667
Erro de Código Complementar Municipal não localizado/exigido na emissão de NFS-e || 7.6667
Erro de numeração/sequência do RPS na emissão de NFS-e || 7.6667
Lançamentos/extratos duplicados na conciliação bancária || 7.6667
Erro na emissão de nota fiscal de remessa/devolução || 7.6667
Descoberta: localizar/recuperar o ID de suporte do chamado || 7.6667
Divergência entre fluxo de caixa mensal e diário || 7.6667
Taxa/desconto no boleto de cobrança aplicado sem constar no contrato ou diferente do esperado || 7.6667
Valor da NFS-e diverge do valor do boleto/contas a receber || 7.6667
Estoque: saldo incorreto ou não movimenta corretamente || 6.6667
Instabilidade recorrente na emissão de NFS-e na prefeitura de Goiânia (ABRASF 2.04 desativado) || 6.6667
Descoberta: emitir notas fiscais em massa/comissão via integração Shopee || 6.6667
Descoberta: ajustar/conciliar lançamentos manualmente para igualar saldo bancário || 6.6667
Ativação da Conta PJ demorada/status pendente || 6.6667
Erro ao criar/salvar novo usuário no sistema || 6.6667
Descoberta: dar acesso ao contador/escritório parceiro || 6.6667
Descoberta: como regularizar pagamento para liberar acesso bloqueado || 6.6667
Falha/instabilidade na integração bancária do Sicredi (extratos, permissão, conexão) || 6.6667
Descoberta: criar/incluir novo usuário || 6.6667
Busca automática de NFS-e/NF-e não retorna ou falha (configuração/credencial) || 6.6667
Falha/instabilidade na integração bancária do Sicredi (autorização/conexão não completa) || 6.6667
Autorização de múltiplos sócios trava integração via Open Finance || 6.6667
Descoberta: como abrir chamado / registrar reclamação || 6.6667
Descoberta: configurar/gerar o DRE || 6.6667
Descoberta - gerenciar/transferir perfil de administrador da conta || 6.3333
Chamado/atendimento: status e prazo sem resolução || 5.3333
Pagamento da assinatura feito em duplicidade (boleto + cartão/Pix) — pedido de estorno || 5
Boleto pago não baixado/creditado após pagamento || 4.3333
Erro ao habilitar/emitir NFS-e pelo Emissor/Portal Nacional (município não reconhecido) || 4.3333
Nota fiscal aparece com falha no sistema mesmo emitida corretamente na prefeitura || 4.3333
Estorno não recebido após cancelamento dentro do prazo de arrependimento (7 dias) || 4.3333
Bloqueio de acesso ao sistema por motivo diverso ou não especificado (fora do fluxo direto de pagamento) || 4.3333
DRE/relatório com valores divergentes dos lançamentos || 4.3333
Falha ao gerar/emitir boleto ou cobrança (erro genérico) ||
Erro falso de 'sem conexão com a internet' bloqueia login/acesso ao sistema ||
Erro E0713 na emissão de nota fiscal ||
Boleto/fatura não chega ao e-mail do cliente (falha de entrega) ||
Erro E415 na emissão de nota fiscal (desconto indevido) ||
Importação de arquivo da Shopee falha na emissão de notas (NBS / tributação IBS-CBS / reprocessamento) ||
Dúvida/erro de configuração de CFOP/CSOSN em nota fiscal ||
Cancelamento de plano/licença solicitado não é efetivado (continua ativo/cobrando) ||
Erro de inscrição estadual do destinatário na emissão de NF-e (SEFAZ) ||
Erro ao pagar boletos ||
Descoberta: migrar a conta de um escritório contábil para outro ||
Nota fiscal importada ou emitida duplica venda/recebível (fica 'Aguardando venda' ou em aberto) ||
Dúvida sobre consulta/boleto do Serasa ||
Descoberta: gerar remessa bancária (arquivo de boleto) para o banco ||
Instabilidade/erro genérico de comunicação com a prefeitura na emissão de NFS-e ||
Cobrança/boleto com vencimento em fim de semana: juros indevidos ou cliente não recebe ||
Cliente com dois IDs de suporte (cadastro duplicado) ||
Dúvida sobre processo de conciliação bancária ||
Tela branca / CA Pro instável e inacessível ||
Dúvida genérica sobre uso do sistema ||
Boleto emitido aparece como 'não registrado' impedindo pagamento ||
Falha de importação/conciliação via arquivo OFX ||
NFS-e rejeitada por sistema não reconhecer opção pelo Simples Nacional ||
Bloqueio de saldo/antecipação/transferência na Conta PJ ||
Cobrança de multa/juros incorreta ou não aplicada em boletos ||
Integração bancária com o Banco Inter parada/atrasada ||
Bloqueio de conta por suspeita de segurança impede acesso (fora do fluxo de pagamento) ||
Descoberta: emitir 2ª via de boleto/nota fiscal ||
Erro E232 na transmissão de NFS-e para a prefeitura ||
Integração bancária com o Sicredi/Sicoob com lançamentos duplicados/ausentes ||
Erro de validação de dados do tomador (CEP/cadastro) na emissão de NFS-e ||
Funcionária não consegue acessar Conta PJ / opção Gestão de Usuários some ||
Faturamento automático de venda recorrente falha ao gerar nota fiscal no dia programado ||
Empresa/filial não habilitada na SEFAZ para emissão de NF-e ||
Conciliação/baixa automática indevida sem autorização ||
NFS-e rejeitada por retenção de ISS não reconhecida/configurada ||
Erro 'Não foi possível identificar/autenticar o cliente' ao acessar conta do cliente ||
Descoberta: centro de custo (cadastrar, ratear e gerar relatório por centro) ||
Produtos desconhecidos com códigos estranhos aparecem automaticamente no sistema ||
Descoberta: enviar áudio/imagem no chat de atendimento ||
Descoberta: adquirir certificado digital A1 e emitir a primeira nota fiscal ||
Descoberta: PDV / frente de caixa e maquininhas (cadastro, integração, sangria) ||
Dúvida: como lançar/conciliar estorno (cartão, pagamento devolvido) ||
Erro/instabilidade no envio da NF-e para a SEFAZ ||
Integração Shopee: vendas/relatório de vendas não são registrados ou validados ||
Links de pagamento: cliente não consegue pagar parcelas e contratos de 12 meses geram só 11 vendas ||
''', '\n')) AS linha
  WHERE TRIM(linha) != ''
), p AS (
  -- separador '||' sem espacos: as linhas sem valor terminam em ' ||' e nao conteriam ' || '
  SELECT TRIM(SPLIT(linha, '||')[OFFSET(0)]) AS nome,
    SAFE_CAST(NULLIF(TRIM(SPLIT(linha, '||')[SAFE_OFFSET(1)]), '') AS FLOAT64) AS mencoes_v2_20261019
  FROM raw
)
-- ids por ordem alfabetica do nome (nao revelam a ordem da verdade)
SELECT FORMAT('S%03d', ROW_NUMBER() OVER (ORDER BY nome)) AS id, nome, mencoes_v2_20261019 FROM p;

SET catalogo_txt = (
  SELECT STRING_AGG(CONCAT(id, ' | ', nome), '\n' ORDER BY id)
  FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_cat`);

-- ----------------------------------------------------------------------------------------------------
-- 3) P1 = EXTRACAO (sem catalogo): campos por item, para o agente nao precisar "ler e entender" tudo
-- ----------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_suporte_p1`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH gerado AS (
  SELECT cid, rep,
    AI.GENERATE(
      CONCAT("""PAPEL: Você classifica resumos de atendimentos de suporte de um ERP SaaS (Conta Azul).
TAREFA: Para o RESUMO abaixo, devolva os campos pedidos.

<REGRAS>
- ruido: true se o resumo é saudação, teste, abandono, ou não descreve nenhum problema ou pedido.
- grao: "friccao" se algo quebrou, diverge ou não funciona; "descoberta" se o cliente pergunta como fazer, onde achar ou se é possível, sem relatar defeito.
- assunto: em "friccao", o problema ESPECÍFICO na linguagem do cliente, em uma frase estável (ex.: "Boleto pago não baixado", não "boleto"). Em "descoberta", no padrão "Descoberta: <feature>" (ex.: "Descoberta: emitir NFS-e"), sem balde genérico.
- natureza: UM de bug, usabilidade, comercial, dúvida, infra, gap, operacional, ruído. Se o produto funciona como desenhado e o cliente só não conhecia a regra, é dúvida, não bug. Cliente cobrando status ou prazo do próprio chamado é operacional.
- O texto do resumo pode ter letras faltando (ex.: "ncelar" = "cancelar"); infira o sentido.
- Não invente: se o resumo é vago, use ruido true.
</REGRAS>

<FORMATO>
Responda com um json no seguinte formato
{"ruido": false, "grao": "friccao", "assunto": "Boleto pago não baixado", "natureza": "bug"}
</FORMATO>

Antes de responder, valide que o JSON é válido. Retorne SOMENTE o JSON (sem formatação de Markdown). Aqui está o resumo:
""", resumo),
      connection_id => 'us.vertex_connection',
      endpoint => 'gemini-3.1-flash-lite',
      model_params => JSON '{"labels":{"ca_initiative":"voc_v0","ca_application_name":"bigquery"},"generation_config":{"thinking_config":{"thinking_budget":0},"temperature":0.0,"maxOutputTokens":600,"responseMimeType":"application/json"}}'
    ) AS r
  FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_pop`, UNNEST(GENERATE_ARRAY(1, n_reps)) AS rep
), lido AS (
  SELECT cid, rep, r.status AS llm_status, r.result AS bruto, ARRAY_LENGTH(REGEXP_EXTRACT_ALL(r.result, r'\{')) AS n_objetos, COALESCE(REGEXP_EXTRACT(r.result, r'(?s)(\{.*?\})'), r.result) AS json_str FROM gerado
)
SELECT cid, rep, llm_status, n_objetos, bruto, SAFE.PARSE_JSON(json_str) IS NOT NULL AS json_valido,
  LOWER(JSON_VALUE(json_str, '$.ruido')) = 'true' AS ruido,
  JSON_VALUE(json_str, '$.grao') AS grao,
  JSON_VALUE(json_str, '$.assunto') AS assunto,
  JSON_VALUE(json_str, '$.natureza') AS natureza
FROM lido;

-- ----------------------------------------------------------------------------------------------------
-- 4) P2 = CASAMENTO com o catalogo (lista fechada com ids): o Gemini faz o "match" que hoje o Claude faz no Passo 3
-- ----------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE `contaazul-datalake-dev.dataform.tmp_aux_suporte_p2`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS
WITH gerado AS (
  SELECT cid, rep,
    AI.GENERATE(
      CONCAT("""PAPEL: Você casa resumos de atendimentos de suporte (ERP SaaS, Conta Azul) com um CATÁLOGO de problemas já conhecidos.
TAREFA: Para o RESUMO abaixo, escolha no CATÁLOGO o item que descreve o MESMO problema específico e devolva o id dele.

<CATALOGO>
""", catalogo_txt, """
</CATALOGO>

<REGRAS>
- match_id: o id do catálogo (ex.: "S017") quando é o MESMO problema específico (mesmo sintoma, mesmo objeto/feature, mesmo pedido do cliente). PREFIRA casar. Só deixe vazio ("") se claramente nenhum item do catálogo descreve o caso.
- Itens "Descoberta: <feature>" são para quando o cliente PERGUNTA como fazer/onde achar/se é possível, sem relatar defeito. Se há defeito, case com o item de problema, não com o de descoberta.
- assunto_rascunho: preencha SOMENTE se match_id é vazio: o problema específico na linguagem do cliente, uma frase (ou "Descoberta: <feature>" se for dúvida de uso).
- natureza: UM de bug, usabilidade, comercial, dúvida, infra, gap, operacional, ruído.
- ruido: true se o resumo é saudação, teste, abandono, ou não descreve nenhum problema ou pedido.
- O texto do resumo pode ter letras faltando (ex.: "ncelar" = "cancelar"); infira o sentido.
- Nunca invente um id fora do catálogo.
</REGRAS>

<FORMATO>
Responda com um json no seguinte formato
{"ruido": false, "match_id": "S017", "assunto_rascunho": "", "natureza": "bug"}
</FORMATO>

Antes de responder, valide que o JSON é válido. Retorne SOMENTE o JSON (sem formatação de Markdown). Aqui está o resumo:
""", resumo),
      connection_id => 'us.vertex_connection',
      endpoint => 'gemini-3.1-flash-lite',
      model_params => JSON '{"labels":{"ca_initiative":"voc_v0","ca_application_name":"bigquery"},"generation_config":{"thinking_config":{"thinking_budget":0},"temperature":0.0,"maxOutputTokens":600,"responseMimeType":"application/json"}}'
    ) AS r,
    LENGTH(catalogo_txt) + LENGTH(resumo) AS chars_prompt_variavel
  FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_pop`, UNNEST(GENERATE_ARRAY(1, n_reps)) AS rep
), lido AS (
  SELECT cid, rep, chars_prompt_variavel, r.status AS llm_status, r.result AS bruto, ARRAY_LENGTH(REGEXP_EXTRACT_ALL(r.result, r'\{')) AS n_objetos,
    COALESCE(REGEXP_EXTRACT(r.result, r'(?s)(\{.*?\})'), r.result) AS json_str FROM gerado
)
SELECT cid, rep, chars_prompt_variavel, llm_status, n_objetos, bruto, SAFE.PARSE_JSON(json_str) IS NOT NULL AS json_valido,
  LOWER(JSON_VALUE(json_str, '$.ruido')) = 'true' AS ruido,
  NULLIF(TRIM(JSON_VALUE(json_str, '$.match_id')), '') AS match_id,
  NULLIF(TRIM(JSON_VALUE(json_str, '$.assunto_rascunho')), '') AS assunto_rascunho,
  JSON_VALUE(json_str, '$.natureza') AS natureza
FROM lido;

-- =====================================================================================================
-- 5) RESULTADOS — rode uma consulta por vez
-- =====================================================================================================

-- R1) Diagnostico das chamadas: validade do JSON e status, por variante
SELECT 'P1 extracao' AS variante, COUNT(*) AS chamadas, COUNTIF(json_valido) AS json_valido,
  COUNTIF(llm_status IS NOT NULL AND llm_status != '') AS com_status_erro, COUNTIF(ruido) AS ruido
FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_p1`
UNION ALL
SELECT 'P2 casamento', COUNT(*), COUNTIF(json_valido), COUNTIF(llm_status IS NOT NULL AND llm_status != ''), COUNTIF(ruido)
FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_p2`;

-- R2) Populacao e baldes (confere se a selecao reproduz ~705 da V2) + cobertura do casamento por balde
SELECT p.balde, COUNT(*) AS conversas, ROUND(SUM(p.peso), 0) AS mencoes_escaladas,
  COUNTIF(m.match_id IS NOT NULL) AS casadas, COUNTIF(m.match_id IS NULL AND NOT m.ruido) AS sem_match, COUNTIF(m.ruido) AS ruido,
  ROUND(100 * COUNTIF(m.match_id IS NOT NULL) / COUNT(*), 1) AS pct_casadas
FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_pop` p
LEFT JOIN `contaazul-datalake-dev.dataform.tmp_aux_suporte_p2` m ON m.cid = p.cid AND m.rep = 1
GROUP BY p.balde ORDER BY conversas DESC;

-- R3) RANKING do dia: Gemini (P2) vs V2 prod. Correlacao, sobreposicao do top-20 e erro relativo no top-30
WITH g AS (
  SELECT m.match_id, SUM(p.peso) AS gem
  FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_p2` m
  JOIN `contaazul-datalake-dev.dataform.tmp_aux_suporte_pop` p USING (cid)
  WHERE m.rep = 1 AND m.json_valido AND NOT m.ruido AND m.match_id IS NOT NULL
  GROUP BY 1
), j AS (
  SELECT c.id, c.nome, c.mencoes_v2_20261019 AS v2, IFNULL(g.gem, 0) AS gem
  FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_cat` c LEFT JOIN g ON g.match_id = c.id
  WHERE c.mencoes_v2_20261019 IS NOT NULL
), r AS (
  SELECT *, RANK() OVER (ORDER BY v2 DESC) AS rk_v2, RANK() OVER (ORDER BY gem DESC) AS rk_gem FROM j
)
SELECT COUNT(*) AS sinais_com_verdade,
  ROUND(SUM(v2), 0) AS soma_v2, ROUND(SUM(gem), 0) AS soma_gemini,
  ROUND(CORR(v2, gem), 3) AS pearson,
  ROUND(CORR(rk_v2, rk_gem), 3) AS spearman_aprox,
  COUNTIF(rk_v2 <= 20 AND rk_gem <= 20) AS top20_em_comum,
  COUNTIF(rk_v2 <= 10 AND rk_gem <= 10) AS top10_em_comum,
  ROUND(AVG(IF(rk_v2 <= 30, ABS(gem - v2) / v2, NULL)), 3) AS erro_relativo_medio_top30
FROM r;

-- R3b) Detalhe do top-30 da V2 lado a lado com o Gemini
WITH g AS (
  SELECT m.match_id, SUM(p.peso) AS gem, COUNT(*) AS conversas
  FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_p2` m
  JOIN `contaazul-datalake-dev.dataform.tmp_aux_suporte_pop` p USING (cid)
  WHERE m.rep = 1 AND m.json_valido AND NOT m.ruido AND m.match_id IS NOT NULL
  GROUP BY 1
)
SELECT c.nome, c.mencoes_v2_20261019 AS v2, ROUND(IFNULL(g.gem, 0), 1) AS gemini, IFNULL(g.conversas, 0) AS conversas_gemini
FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_cat` c LEFT JOIN g ON g.match_id = c.id
WHERE c.mencoes_v2_20261019 IS NOT NULL
ORDER BY c.mencoes_v2_20261019 DESC LIMIT 30;

-- R4) Residual: o que o Gemini NAO casou (o trabalho que ainda sobraria para o Claude nomear/consolidar)
SELECT LOWER(assunto_rascunho) AS assunto_rascunho, COUNT(*) AS conversas
FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_p2`
WHERE rep = 1 AND json_valido AND NOT ruido AND match_id IS NULL
GROUP BY 1 ORDER BY conversas DESC LIMIT 40;

-- R5) Concordancia interna P1 x P2 (mesma conversa): grao e natureza; e coerencia de natureza entre variantes
SELECT COUNT(*) AS conversas,
  COUNTIF(a.natureza = b.natureza) AS natureza_igual,
  ROUND(100 * COUNTIF(a.natureza = b.natureza) / COUNT(*), 1) AS pct_natureza_igual,
  COUNTIF(a.ruido = b.ruido) AS ruido_igual,
  COUNTIF(a.grao = 'descoberta') AS p1_descoberta
FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_p1` a
JOIN `contaazul-datalake-dev.dataform.tmp_aux_suporte_p2` b ON a.cid = b.cid AND a.rep = 1 AND b.rep = 1
WHERE a.json_valido AND b.json_valido;

-- R6) Autoconsistencia (so se n_reps = 2): o mesmo resumo cai no mesmo id nas duas repeticoes?
SELECT 
  COUNT(*) AS conversas, 
  COUNTIF(IFNULL(a.match_id, '') = IFNULL(b.match_id, '')) AS mesmo_match,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(IFNULL(a.match_id, '') = IFNULL(b.match_id, '')), COUNT(*)), 1) AS pct_mesmo_match
FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_p2` a
JOIN `contaazul-datalake-dev.dataform.tmp_aux_suporte_p2` b 
  ON a.cid = b.cid AND a.rep = 1 AND b.rep = 2;

-- R7) Tamanho e custo estimado (4 caracteres por token; US$ 0,25/M entrada e US$ 1,50/M saida, precos de agregadores)
SELECT COUNT(*) AS chamadas,
  ROUND(AVG(chars_prompt_variavel), 0) AS chars_variaveis_medio,
  ROUND(AVG(chars_prompt_variavel) / 4 + 450, 0) AS tokens_entrada_por_chamada_aprox,
  ROUND(COUNT(*) * (AVG(chars_prompt_variavel) / 4 + 450) / 1e6 * 0.25 + COUNT(*) * 45 / 1e6 * 1.5, 2) AS usd_dia_p2_aprox
FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_p2` WHERE rep = 1;

-- R8) Amostra para ROTULO HUMANO (inicio do conjunto rotulado): 20 casadas + 20 sem match, com o resumo e a decisao do Gemini
(SELECT 'casada' AS grupo, p.cid, p.balde, p.resumo, c.nome AS sinal_escolhido, m.assunto_rascunho, m.natureza
 FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_p2` m
 JOIN `contaazul-datalake-dev.dataform.tmp_aux_suporte_pop` p USING (cid)
 JOIN `contaazul-datalake-dev.dataform.tmp_aux_suporte_cat` c ON c.id = m.match_id
 WHERE m.rep = 1 AND m.json_valido AND NOT m.ruido 
 ORDER BY FARM_FINGERPRINT(p.cid) 
 LIMIT 20)
UNION ALL
(SELECT 'sem_match', p.cid, p.balde, p.resumo, CAST(NULL AS STRING), m.assunto_rascunho, m.natureza
 FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_p2` m
 JOIN `contaazul-datalake-dev.dataform.tmp_aux_suporte_pop` p USING (cid)
 WHERE m.rep = 1 AND m.json_valido AND NOT m.ruido AND m.match_id IS NULL 
 ORDER BY FARM_FINGERPRINT(p.cid) 
 LIMIT 20);

-- R9) (v2) Diagnostico dos JSON invalidos: o resultado bruto tem mais de 1 objeto? (hipotese: resumo com varias perguntas => o modelo devolve 1 JSON por pergunta)
SELECT 'P1' AS variante, COUNT(*) AS invalidos, COUNTIF(n_objetos > 1) AS com_varios_objetos, COUNTIF(IFNULL(n_objetos, 0) = 0) AS sem_objeto
FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_p1` WHERE NOT json_valido
UNION ALL
SELECT 'P2', COUNT(*), COUNTIF(n_objetos > 1), COUNTIF(IFNULL(n_objetos, 0) = 0)
FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_p2` WHERE NOT json_valido;

-- R9b) 20 exemplos do texto bruto dos invalidos (P1 e P2)
SELECT 'P1' AS variante, cid, n_objetos, SUBSTR(bruto, 1, 400) AS bruto FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_p1` WHERE NOT json_valido ORDER BY FARM_FINGERPRINT(cid) LIMIT 10;
SELECT 'P2' AS variante, cid, n_objetos, SUBSTR(bruto, 1, 400) AS bruto FROM `contaazul-datalake-dev.dataform.tmp_aux_suporte_p2` WHERE NOT json_valido ORDER BY FARM_FINGERPRINT(cid) LIMIT 10;