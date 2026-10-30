# Fontes de dados dos agentes do Sense 2.0 em produção

30/10/2026. Levantamento das tabelas de consulta de cada agente, com nomes completos.

**Fonte:** seção de fontes de cada prompt em `routines/prod/` do repositório `sense-platform` (`agente-especialista-suporte-v2.md`, `-nps.md`, `-portalideias.md`, `-onboarding.md`, `agente-cross.md`, `agente-acompanhamento-entregas.md`) e os scripts SQL de `routines/prod/scripts/agente-especialista-portalideias/sql/`.

**Conferências feitas:**
- BigQuery de produção (`contaazul-ssbi`): confirmei que as tabelas existem (`INFORMATION_SCHEMA`) e consultei o histórico de jobs dos últimos 30 a 45 dias. O histórico não identifica o agente (as consultas aparecem sob usuários humanos), então ele só serve como indício de uso.
- Notion: Central do Sense, hubs dos especialistas e Registro de Fontes (só o esquema; não li as linhas). Essas páginas estão sob "Legado", marcadas como não verificadas, com última edição em ago/set 2026.

Todas as tabelas ficam no projeto `contaazul-ssbi`; abaixo vão como `dataset.tabela`.

## Tabelas por agente (BigQuery, somente leitura)

| Agente | Tabela | Papel | Fora do BigQuery |
|---|---|---|---|
| **Suporte V2** | `silver_serve.ingestion_intercom_conversations` | Universo do dia e fonte da clusterização (`ai_issue_summary`, `sentiment`, `support_code`). | Notion: Sinais V2 e Dashboard V2 |
| | `silver_serve.ingestion_intercom_messages` | O `message_body`, lido só na `Leitura` dos clusters que chegam ao topo. | |
| | `gold_serve.dim_zendesk_tickets_detailed` | Seleção N2/N3 (`ticket_level`) e enriquecimento (`time_to_solved`, `customer_type`). | |
| **pNPS** | `gold_nps.fact_nps_survey` | NPS e Survicate, CA Pro e CA Mais, uma linha por resposta. | Notion: Sinais, Resultado mensal e Histórico de perfis |
| | `gold_common.dim_company` | Perfil da empresa. | |
| | `gold_capro_features.fact_capro_features` | Amplitude de uso (CA Pro). | |
| | `gold_partners.fact_partner_revenue` e `gold_partners.fact_customer_partner_profile` | Perfis do CA Mais. | |
| | `gold_serve.dim_zendesk_tickets_detailed` | Contexto de suporte. | |
| | `silver_ds_churn.churn_score_prediction` | Churn. | |
| **Portal de Ideias** | `silver_ideas_portal.ideas_portal` | Fonte das ideias. | Notion: Sinais e Reports |
| | `gold_strategy.dim_voc_full_category` | Categorização da VoC. | |
| | `gold_common.dim_company` | Perfil da empresa. | |
| | `tmp_data_analytics.sense_ideas_portal_cluster_map`, `sense_ideas_portal_cluster_meta`, `sense_ideas_portal_votes_snapshot` e a view `sense_ideas_portal_clusters` | Tabelas que o próprio agente cria e mantém. Existe também `sense_ideas_portal_backfill_staging`, usada na carga do backfill. | |
| **Onboarding** | `gold_onboarding.dim_onboarding_meetings` | Reuniões de onboarding. | MeetRox: API `api.meetrox.ai/v1/calls` por `curl` (transcrições). Notion: Sinais e Reports |
| | `gold_onboarding.fact_onboarding_activation` | Ativação por empresa (é o "Salesforce" da Central). | |
| | `gold_onboarding.fact_onboarding_funnel` | Etapas do funil. | |
| | `gold_common.dim_company` | Perfil da empresa. | |
| **Cross** | `silver_master_data.company` | Churn, usado só se um sinal trouxer o dado. | Notion: Registro de Fontes, OPs, OKR e Change-Log. Arquivos locais: `coverage_view.jsonl` e `estrategia-destilada.md` |
| **Acompanhamento de Entregas** | Nenhuma | | Só Notion |

## Divergências com o Notion e com versões anteriores

- **"Amplitude" do pNPS:** na Central, é a amplitude de features (`gold_capro_features.fact_capro_features`), não a ferramenta Amplitude. O agente não tem fonte de Amplitude.
- **"Salesforce" do Onboarding:** o agente não lê `silver_onboarding.salesforce_*`. A ativação vem de `gold_onboarding.fact_onboarding_activation`.
- **MeetRox:** a tabela `silver_master_data.meetrox_transcriptions` existe, mas o agente não a usa; o prompt chama a API direto.
- **Zendesk no Suporte:** a Central cita Zendesk como fonte, mas o agente só lê `dim_zendesk_tickets_detailed` para selecionar e enriquecer. O texto analisado é do Intercom.
- **Portal de Ideias:** o Notion abreviava os nomes como `ideas_portal_*` e a Central dizia "gold própria". Não há gold nativa: o agente usa `silver_ideas_portal` mais as tabelas `sense_ideas_portal_*` em `tmp_data_analytics`.
- **Cross e BigQuery:** o prompt se contradiz. O trecho de fontes (linha 138) lista `silver_master_data.company`, mas a tabela de ferramentas (linha 715) diz "zero BigQuery". Prevalece a leitura de que o Cross só consulta churn se um sinal trouxer o dado.

## Fora do escopo desta tabela

- `gold_strategy.dim_voc_full_category` (Esteira A) alimenta as explores de NPS no Looker e é lida pelo Portal de Ideias. Os demais especialistas não a leem.
- As tabelas `sense_cobertura_casos_uso` e `sense_cobertura_subsegmentos` em `tmp_data_analytics` foram apagadas em outubro e não são fontes de hoje.
