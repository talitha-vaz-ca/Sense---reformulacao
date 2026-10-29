# Links importantes

Links internos exigem acesso à Conta Azul. O link do Miro foi gravado **sem** o parâmetro `share_link_id`, que pode dar acesso ao board.

## Miro

| O quê | Link |
|---|---|
| Board da reformulação (3 quadros: "Hoje", "Proposta" e "Resumo: as is, to be e tbd") | https://miro.com/app/board/uXjVETmgjJA=/ |
| Arquitetura do Sense (board original da equipe) | https://miro.com/app/board/uXjVGhHxhRg=/ |

## Notion

| O quê | Link |
|---|---|
| Sense Central (o que está no ar hoje) | https://app.notion.com/p/3a34a554a42f8118ae36fe0582381266 |
| Suporte: Customer Insights | https://app.notion.com/p/3a44a554a42f80c7bb85cd37d3a141ab |
| Bases e Atributos: Suporte | https://app.notion.com/p/3a44a554a42f80f2b5ecc1d673301534 |
| Arquitetura do report: Suporte | https://app.notion.com/p/3a44a554a42f80b5a1d4cbdc5950a1cb |
| Guia: Score do Suporte | https://app.notion.com/p/3a64a554a42f81b9974ae7efb7d8e921 |
| Manual de seleção de modelo por agente | https://app.notion.com/p/3aa4a554a42f81eda23cf4ac16a9d635 |
| Manual de criação de Especialistas | https://app.notion.com/p/3a54a554a42f81a298cccc3a63e31478 |
| Categorização VoC por LLM: como funciona | https://app.notion.com/p/3cd4a554a42f816d969ee2018ad2182f |
| Taxonomia VoC: proposta v1 | https://app.notion.com/p/3ca4a554a42f81cea93dfd3ed457a054 |
| Suporte CA: página de trabalho [PROD] (HUB) | https://www.notion.so/3bb4a554a42f812fb312fb6e5dea9c46 |
| Logs de Execução: Sense [PROD] | https://www.notion.so/76327b98e80a4e078af3a56c17745c97 |
| Registro de Fontes de Sinais: Sense 2.0 | https://www.notion.so/9228f8f904f442ed97192d6832c92142 |
| Oportunidades: Sense 2.0 (board principal) | https://www.notion.so/59329b295bfb47f7800877a80256021a |

### Bases do Notion usadas como "verdade" nos testes (data sources)

| Base | `data_source_id` |
|---|---|
| Sinais do Suporte V2 (prod) | `e7ab0182-c700-4d19-b9f1-5107fa7d37b0` |
| Sinais do pNPS (prod) | `44f63463-1651-4651-83cf-93d062a11a51` |
| Logs de Execução (prod) | `dcb5ae1d-8e21-4f77-b9d4-0f757b68591f` |

## GitHub

| O quê | Link |
|---|---|
| Prompts executáveis dos agentes (`routines/prod/*`) | https://github.com/ContaAzul/sense-platform |
| Taxonomia DDD (documentação viva) | https://github.com/ContaAzul/documentation |
| Prompt do Suporte V2 (prod) | `routines/prod/agente-especialista-suporte-v2.md` no repositório `sense-platform` |

## BigQuery e Dataform

| Tabela | Uso |
|---|---|
| `contaazul-ssbi.gold_strategy.dim_voc_full_category` | VoC consolidado de 7 fontes, classificado por LLM (o prompt fica na coluna `full_prompt`) |
| `contaazul-ssbi.silver_serve.ingestion_intercom_conversations` | Conversas do Intercom; `ai_issue_summary` vem do atributo "AI Issue summary" |
| `contaazul-ssbi.silver_serve.ingestion_intercom_messages` | Mensagens (`message_body`), usadas só na Leitura |
| `contaazul-ssbi.gold_serve.dim_zendesk_tickets_detailed` | Tickets do Zendesk (N2/N3, tempo, perfil); grão de ticket |
| `contaazul-ssbi.gold_nps.fact_nps_survey` | Respostas e comentários de NPS (fonte do pNPS) |
| `contaazul-ssbi.silver_ideas_portal.ideas_portal` | Ideias do portal (fonte do Portal) |
| `contaazul-ssbi.tmp_data_analytics.sense_ideas_portal_cluster_map` e `..._cluster_meta` | Backfill de clusters do Portal (mapa id para cluster, e metadados) |
| `contaazul-datalake-dev.dataform.tmp_aux_*` | Tabelas temporárias dos testes AUX (expiram em 7 dias) |
| `contaazul-datalake-dev.dataform.tmp_sim_suporte_20261019_*` | Tabelas temporárias da simulação do dia 19/10 |

Arquivo do Dataform da ingestão do Intercom: `definitions/silver/serve/tables/ingestions/ingestion_intercom_conversations.sqlx`.

## Este repositório

https://github.com/talitha-vaz-ca/Sense---reformulacao
