# Sense: reformulação

Pasta de trabalho da reformulação do **Sense 2.x** (a esteira de agentes que transforma a voz do cliente em oportunidades de produto na Conta Azul). Reúne propostas de arquitetura, testes com Gemini, resultados, scripts SQL e o histórico das decisões.

**Estado em 30/10/2026.** Nada aqui altera produção. Os testes rodaram em `contaazul-datalake-dev`, com leituras de prod. Os números de custo vêm de estimativas por tokens (DB de Logs do Notion), não de fatura.

> **Atenção antes de compartilhar.** Esta pasta tem conteúdo interno da Conta Azul (arquitetura do data lake, custos dos agentes, IDs de bases do Notion) e, nas pastas `*_output/`, texto de clientes (resumos de atendimento, comentários de NPS, ideias do portal) com alguns e-mails. Veja a seção "Dados sensíveis" no fim.

## Em uma página

| Pergunta | Resposta hoje |
|---|---|
| Como o Sense funciona? | 5 agentes standalone no ar (Suporte V2, pNPS, Onboarding, Portal de Ideias, Cross), todos rodando em sessões do **Claude**. Fora dele, o Gemini 3.1 flash-lite já roda no data lake (`dim_voc_full_category` e resumo do MeetRox, via `AI.GENERATE`) e o `ai_issue_summary` é um atributo do Intercom; nenhum deles faz o trabalho dos agentes. |
| Quanto custa? | ~**US$ 360 por mês** (estimado; set US$ 359, out US$ 367). Onboarding ~63%, Suporte V2 ~26%, Cross ~9%. |
| O que o Suporte V2 lê? | **30%** da população: em 19/10, 707 de 1.961 conversas com resumo (censo N2/N3 e muito negativo mais 30% do resto). Contagens são estimativas (x3,33). |
| Custo e tempo do Suporte V2 | ~US$ 2,5 e ~380 mil tokens por run, diário, ~22 min. A maior parte do gasto é o raciocínio do Claude, não o tamanho do texto. |
| Um LLM auxiliar (Gemini 3.1 flash-lite) ajuda? | **pNPS:** sim, é o melhor candidato (JSON 99,7%, Spearman 0,89 contra o agente). **Suporte:** ainda não substitui o casamento do Claude (Spearman 0,60 contra um teto de 0,86 da amostragem). **Portal:** inconclusivo. |
| Quanto custaria a camada Gemini? | **~US$ 42–65/mês** (Suporte em 100% ~US$ 35–55; Onboarding em paralelo ~US$ 6–10; pNPS e Portal, centavos), além dos ~US$ 360 do Claude e dos ~US$ 72 da `dim_voc`. Só o Onboarding tem potencial de reduzir o custo total, e depende de rever a regra I5 (hipótese; ver `HISTORICO.md`, seção 3.7). |
| Qual o próximo passo? | Rodar o Gemini em 100% **em paralelo**, sem escrever em nada, por 2 a 3 semanas, e usar as divergências com a V2 como fila de rótulo para o time de Suporte. |

## Mapa dos arquivos

### 1. Contexto e propostas de arquitetura

| Arquivo | O que é |
|---|---|
| `sense-reformulacao-contexto.md` | Contexto da reformulação: Intercom, VoC, volumes, grão |
| `conversa-sense-reformulacao.md` | Conversa que originou a proposta de reformulação do Sense 2.x |
| `propose-voc-generica-e-especialistas.md` | Proposta: VoC genérica mais VoC especialista por área (antes e depois) |
| `proposta-colunas-dim-voc-e-agente-suporte-v3.md` | O que embutir na `dim_voc` para aliviar o agente de Suporte e o desenho do Suporte V3 |
| `arquitetura-tabelas-voc-dataform.md` | Arquitetura das tabelas VoC no Dataform (idempotência, D-1 íntegro) |
| `investigacao-dev-dim-voc-full-category.md` | Investigação da `dim_voc_full_category` no dev |
| `sense-reformulacao-regras-suporte-no-gemini.md` | Regras do agente de Suporte levadas para a `dim_voc_full_category` |
| `varredura-sense-metabase-looker.md` | Varredura de Metabase e Looker sobre o Sense |
| `fontes-de-dados-agentes-sense-2.0.md` | Tabelas de cada agente em produção, conferidas nos prompts de `routines/prod/`, no BigQuery e no Notion |

### 2. Teste A + B (prompt de produção mais campos novos de Suporte)

| Arquivo | O que é |
|---|---|
| `teste_prompt_suporte_3_tickets.sql`, `teste_prompt_suporte_amostra_comparativo.sql`, `teste_prompt_suporte_amostra_comparativo_v2.sql` | Scripts dos testes em 3 e em 33 tickets (BigQuery `AI.GENERATE`) |
| `resultados-teste-prompt-suporte-gemini.md` | Análise das 4 rodadas (Gemini 2.5 e 3.1) |
| `resumo-executivo-teste-prompt-suporte-gemini.md` | Resumo executivo |
| `resultados-teste-prompt-suporte/*.json` | Dados brutos das rodadas e da simulação do dia |
| `simulacao_dia_suporte_2026-10-19.sql` | Simulação de um dia completo (19/10) |
| `simulacao-dia-2026-10-19-sense2-vs-ab.md` | Resultado da simulação do dia |
| `comparativo-ab-vs-sense2-0.md` | Comparativo A + B contra o Sense 2.0: volume, tempo, tokens, custo, assertividade |

### 3. Design do Suporte V2 e testes de LLM auxiliar nos outros agentes

| Arquivo | O que é |
|---|---|
| `justificativa-design-agente-suporte-v2.md` | Por que a V2 foi desenhada assim (26 decisões, linha do tempo, tensões) |
| `plano-testes-llm-auxiliar-gemini-outros-agentes.md` | Plano de testes AUX (Suporte, pNPS, Portal, Onboarding, Cross) |
| `teste_aux_gemini_suporte_catalogo.sql` | AUX-S: casamento com o catálogo de sinais |
| `teste_aux_gemini_pnps.sql` | AUX-N: rótulos N1 e N2 por comentário |
| `teste_aux_gemini_portal_ideias.sql`, `teste_aux_gemini_portal_ideias_v2.sql` | AUX-P: tema e cluster (o v2 corrige o catálogo por tema) |
| `resultados-teste-aux-gemini.md` | Resultados, rodada 2, linha de base e cobertura de 100% (seções 9 a 11) |
| `teste_aux_gemini_*_output/` | CSVs exportados do BigQuery com os resultados de cada consulta |

### 4. Histórico e links

| Arquivo | O que é |
|---|---|
| `HISTORICO.md` | Linha do tempo, decisões, ideias e pendências |
| `LINKS.md` | Links importantes (Miro, Notion, GitHub, BigQuery) |

## Como reproduzir os testes AUX

1. Abra o console do BigQuery no projeto `contaazul-datalake-dev` (é preciso permissão para `AI.GENERATE` e para a conexão `us.vertex_connection`).
2. Rode as seções de criação de tabelas do script (as tabelas `tmp_aux_*` expiram em 7 dias).
3. Rode as consultas de resultado (R1 em diante) uma por vez.
4. O endpoint do `AI.GENERATE` precisa ser um **texto literal** (`'gemini-3.1-flash-lite'`), não uma variável.
5. Custos estimados por script: Suporte ~US$ 0,65, pNPS ~US$ 0,11, Portal v2 ~US$ 1,90, mais ~US$ 1 para a rodada em 100% do Suporte.

## Dados sensíveis

- As pastas `teste_aux_gemini_*_output/` contêm texto de clientes. O arquivo `teste_aux_gemini_suporte_catalogo_output/script_job_291ab3d33895fff0779553f409b2f0dd_13.csv` tem **e-mails de clientes**.
- Os documentos citam custos, tokens por agente e IDs internos de bases do Notion.
- Antes de compartilhar fora da empresa, confira a visibilidade do repositório e remova ou anonimize esses itens.
