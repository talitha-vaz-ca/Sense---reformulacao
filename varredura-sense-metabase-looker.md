# Varredura de Metabase e Looker: conteúdo relacionado ao Sense

Data: 27/10/2026
Projeto: sense - reformulação

## Pergunta

Varrer o Metabase e o Looker em busca de dashboards ou visões relacionadas ao Sense.

## Resultado em uma linha

No Looker, nenhum dashboard tem "Sense" no nome, mas existe o explore `voc_full_category`, que corresponde à `dim_voc_full_category`, além de dashboards de VoC e NPS. O Metabase não pôde ser varrido porque todas as chamadas falharam.

---

## Looker (`contaazul.cloud.looker.com`)

### Buscas feitas em dashboards

| Filtro | Campo | Resultado |
|---|---|---|
| `%sense%` | título | vazio |
| `%sense%` | descrição | vazio |
| `%voc%` | título | 3 dashboards |
| `%voc%` | descrição | vazio |
| `%voz%` | título | vazio |
| `%categor%` | título | 3 dashboards (provavelmente não relacionados) |
| `%nps%` | título | 2 dashboards |

### Dashboards de VoC e NPS

| ID | Título |
|---|---|
| 1092 | Analise de Detratores por VoC - Fev |
| 772 | VoC - Conta PJ |
| 1114 | VoC [Design] CA PRO |
| 1127 | NPS |
| 1144 | NPS Conta PJ |

Os dashboards 1016 (Acompanhamento sugestão das categoria), 953 ([PRO_AI_OFI] Acompanhamento sugestão das categoria) e 1086 (TME por Categoria) apareceram na busca por "categor", mas parecem ser de categorização financeira e TME, sem relação com o Sense.

### Explore mais próximo do Sense

**`voc_full_category`** ("[WIP] Voice of Customer"), no model `nps_data_mart`.

Dimensões relevantes:

- **Classificação por IA:** `categoria_gemini`, `categoria_gemini_full` (lista de categorias do mesmo ticket), `macrotema`, `tipo_de_incidente_gemini` (Dúvida, Incidentes, Ajustes, Sugestão, Reclamação, Elogio, Não é possível determinar) e `sentimento`.
- **Contexto da IA:** `resumo_do_incidente_gemini`, `full_prompt` e `prompt_values`.
- **Origem:** `fonte`, `categoria` (original do sistema), `motivo`, `submotivo`, `tipo_de_chamado`, `ticket_subcategory`, `problem_details` e `url_incidente`.
- **Telefone e NPS:** `transcricao`, `resumo_meetrox` e `nps_answer`.
- **Datas:** `data_*` (iteração), `became_customer_*` (início de relacionamento) e `churn_*`.

### Outros explores no model `nps_data_mart`

- `nps_blended`: respostas de NPS (Survicate), pNPS periódico e rNPS transacional, com casamento heurístico com tickets Zendesk.
- `nps_comments_before_after`: primeira e última resposta de pNPS comentada de cada respondente.
- `nps_cycle_transition`: matriz de transição Detrator/Neutro/Promotor entre o Ciclo 1 e o Ciclo 2.
- `nps_detractor_themes_30d`: temas dominantes nos detratores dos últimos 30 dias, a partir do macrotema classificado por LLM.

### Models que podem ter algo adjacente (não explorados)

- `ombudsman` (Ouvidoria)
- `ai_inbox_data_mart` (AI Captura)
- `clients_360`

### Limitações

- A ferramenta de busca só filtra por título e descrição, então dashboards com outros nomes podem ter ficado de fora.
- Nenhum dashboard foi aberto, então não se sabe quais deles consomem o `voc_full_category`.

---

## Metabase

Quatro chamadas falharam com "Tool execution failed", sem detalhe do erro:

- `search_content` com "sense"
- `search_dashboards` com "sense"
- `list_dashboards`
- `search_content` com "voc"

Pode ser indisponibilidade do conector ou sessão expirada. Vale tentar de novo mais tarde ou reconectar o Metabase.

---

## Próximos passos possíveis

1. Abrir o `voc_full_category` e rodar uma query de amostra.
2. Examinar os dashboards 1092 e 1114 para ver o que consomem.
3. Tentar o Metabase de novo.
4. Explorar `ombudsman`, `ai_inbox_data_mart` e `clients_360`.
