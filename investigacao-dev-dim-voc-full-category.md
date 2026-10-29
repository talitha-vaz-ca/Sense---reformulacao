# Investigação — `dim_voc_full_category` no dev e rearquitetura alinhada ao brainstorm de 27/10

> **Data:** 27/10/2026 · **Projeto:** `contaazul-datalake-dev` · **Acesso:** somente leitura, pelo console do BigQuery no navegador (o MCP do BigQuery devolve `Access Denied` no projeto dev). Complementa `propose-voc-generica-e-especialistas.md` e `arquitetura-tabelas-voc-dataform.md`.

---

## 0. Resumo

1. **No dev não existe `gold_strategy.dim_voc_full_category`.** A cópia que existe é `gold_strategy_dev_ericklemos.dim_voc_full_category`, uma carga única de 27/08/2026 (52.508 linhas, eventos de 28/07 a 27/08), do Erick. Ela tem **24 colunas**: as 21 de prod mais `domain`, `subdomain` e `is_atendimento`.
2. **O que varia dentro de um item é só a categoria.** Nas 6 fontes, `macro_theme`, `sentiment`, `domain`, `incident_type_gemini` e `incident_summary_gemini` têm valor único por item. Só `category_gemini` se multiplica (a única exceção é o Reclame Aqui, que agrupa tickets-filhos). A tabela mistura dois grãos, e a divisão em dados do item e categorias do item sai sem custo de modelagem.
3. **67,5% dos itens de NPS não têm comentário e todos foram ao LLM.** Dos 16.063 itens de NPS, 10.843 têm `reason` vazio. Os 6.099 promotores sem texto saíram quase todos como `Produto` / `Elogio / Satisfação Geral` (em prod, 69,3% dos itens de NPS não têm texto, e os promotores saem como `Relacionamento com a Conta Azul`; ver 2.5). Os 4.744 detratores e neutros sem texto saíram como `Não é possível determinar`. O resultado é função só da nota: não precisa de LLM e infla o tema `Produto`.
4. **O `full_prompt` pesa ~2 GB de texto em 30 dias** (média de 37.964 caracteres por linha, 52.508 linhas), enquanto o dado de cada item (`facts` nos experimentos) tem de 61 a 2.288 caracteres em média. O resto é template repetido.
5. **`sentiment` tem 18 valores distintos** (ex.: `Insatisfação`, `Insatisfeita`, `Raiva`, `Alegria`, `Gratidão`, `Não é possível determinar`). É um campo aberto, sem enum.
6. **`domain` e `subdomain` são novos e ainda não estão utilizáveis:** há valores concatenados (`Financial | Core Accounting & Analytics`), e 89% dos itens de NPS (14.287 de 16.063) estão sem domínio.
7. **O dev já guarda experimentos que apontam para a nova arquitetura** (`dataform.voc_*`, 22–24/09): extração em duas etapas (`facts` → `categoria`), taxonomia de 258 rótulos e nova saída (`macrotema`, `tipo_de_incidente_gemini`, `sentimento`, `subcategoria`, `resumo_do_incidente_gemini`).
8. **Divergência com a reunião:** a ata diz que o Intercom já alimenta o VOC. Na tabela do dev não há linha com `source = 'intercom'`, e a investigação de 26/10 chegou à mesma conclusão para prod. Precisa ser esclarecido o que "VOC" significa para o Philipi e o Erick (ver seção 5).

---

## 1. Onde está cada coisa no dev

| Objeto | Tipo | O que é |
|---|---|---|
| `gold_strategy_dev_ericklemos.dim_voc_full_category` | tabela, criada em 27/08/2026 | Cópia do Erick, 24 colunas, carga única de 30 dias |
| `gold_strategy.daniel_DATA19784_voc_gold_dim_voc_full_category` (+ views `*_voc_gold_*` em `bronze_tool_zendesk`, `silver_marketing`, `silver_master_data`, `silver_retention`, `gold_nps`, `gold_capro_features`, `tmp_data_analytics`) | tabela e views, jun/2026 | Rascunho do Daniel (DATA-19784), anterior |
| `dataform.voc_prompt_v2`, `voc_prompt_v2_result` (5.531 linhas), `voc_sct_prompt` | tabelas, 24/09 | Prompt novo e resultado com a saída reformulada |
| `dataform.voc_subteste_compara` (5.965), `voc_subteste_resultado` / `voc_subteste_final` (6.784), `voc_tax_subteste` / `_labels` (258 rótulos) / `_ping` | tabelas, 22–23/09 | Teste de taxonomia com extração em duas etapas |

Em prod, a tabela (`contaazul-datalake-prod.gold_strategy`) foi modificada pela última vez em 27/10 10:59 (lista de recentes do console). Não consultei as colunas de prod nesta investigação.

---

## 2. Achados medidos (dev, 28/07 a 27/08/2026)

### 2.1 Volume e grão

| Fonte | Linhas | Itens | Itens com mais de 1 linha | Valores distintos de `category_gemini` |
|---|---|---|---|---|
| zendesk | 30.879 | 27.787 | 2.841 (10,2%) | 234 |
| nps | 16.224 | 16.063 | 121 (0,8%) | 137 |
| aquisicao | 4.608 | 4.608 | 0 | 31 |
| Keys-Off | 632 | 629 | 3 | 27 |
| reclame_aqui | 128 | 89 | 26 | 34 |
| ideas_portal | 37 | 34 | 3 | 29 |
| **Total** | **52.508** | **49.210** | | |

Linhas a mais por causa da explosão de categoria: 3.298 (6,3%). Máximo de 10 linhas num item do Zendesk.

**Variação dentro do item** (itens com mais de 1 linha): `category_gemini` varia em 100% deles. `macro_theme`, `domain`, `incident_type_gemini` e `incident_summary_gemini` variam em 0, em todas as fontes. `sentiment` e `full_prompt` variam em 1 item, o do Reclame Aqui.

### 2.2 NPS sem comentário

| Estado | Itens | Resultado do LLM |
|---|---|---|
| Promotor, `reason` vazio | 6.099 | `Produto` / `Elogio / Satisfação Geral` (6.092) ou `Relacionamento com a Conta Azul` (7), sempre com 1 categoria |
| Detrator ou neutro, `reason` vazio | 4.744 | `Não é possível determinar` |
| Com texto, indeterminado | 2.408 | Exemplo de texto: "NADA A FALAR" |
| Com texto, classificado | 2.812 | Tema real |

Em 100% das linhas de NPS `llm_send_status = 'enviado_llm'`; nenhuma ficou como `nao_enviado_sem_info`. Em NPS, 7.152 dos 16.063 itens (44,5%) são indeterminados, e 66% deles não têm texto algum.

Implicações: (a) 10.843 chamadas de LLM (22% de todos os itens da janela) devolvem uma função determinística da nota; (b) o tema `Produto` do NPS está inflado por promotores sem comentário; (c) o indicador "43% indeterminado" da proposta de 26/10 é, na maior parte, ausência de insumo, não falha do modelo.

### 2.3 Largura e qualidade das colunas

| Coluna | Medida | Leitura |
|---|---|---|
| `full_prompt` | média de 37.964 caracteres; 30.097 valores distintos | Template (~30 mil) repetido em cada linha mais o dado do item |
| `transcription` | média de 5.448 caracteres | Texto cru, só relevante para o Zendesk |
| `incident_summary_gemini` | média de 165 caracteres | Resumo curto e útil |
| `sentiment` | 18 valores distintos | Sem enum; mistura gênero e sinônimos |
| `macro_theme` | 8 valores | Estável |
| `incident_type_gemini` | 7 valores | Estável |
| `is_atendimento` | `true` em todas as linhas do Zendesk, `false` nas demais | Redundante com `source = 'zendesk'` |
| `domain` / `subdomain` | itens sem domínio: NPS 14.287, aquisição 769, Zendesk 499; valores concatenados com `|` | Mapeamento categoria → domínio parcial e não atômico |

### 2.4 O que os experimentos de setembro mostram

- `voc_subteste_final`: a entrada do LLM é um bloco `facts` (categoria de origem, tipo, motivo, submotivo, transcrição), com média de 61 (NPS), 88 (aquisição), 165 (Keys-Off), 538 (portal), 1.507 (Reclame Aqui) e 2.288 (Zendesk) caracteres. A saída é uma `categoria` sem nenhuma linha nula.
- `voc_prompt_v2_result` traz `raw` (resposta crua) ao lado das colunas extraídas, o que permite auditar e reprocessar sem nova chamada.

Não abri o SQL desses experimentos nem o do Erick. Falta ler o código para saber como `domain` e `subdomain` são derivados.

---

## 2.5 Verificação em prod (27/10/2026, `contaazul-ssbi.gold_strategy.dim_voc_full_category`, 90 dias até 26/10)

| Pergunta | Resultado em prod | Dev (carga de 27/08) |
|---|---|---|
| Colunas | **21**; não existem `domain`, `subdomain` nem `is_atendimento` | 24 |
| Fontes (`source`) | `zendesk`, `Keys-Off`, `nps`, `reclame_aqui`, `aquisicao`, `ideas_portal`: **nenhuma linha de Intercom** (114.481 itens) | Mesmas 6, sem Intercom |
| Itens de NPS | 18.654 | 16.063 (30 dias) |
| NPS sem texto (`reason` e `problem_details` vazios) | **12.932 (69,3%)**; todos com `llm_send_status = 'enviado_llm'` | 10.843 (67,5%) |
| Promotor sem texto | 7.645: 7.212 saem como `Relacionamento com a Conta Azul` / `Elogio / Satisfação Geral`, 424 como macrotema indeterminado com `Elogio / Satisfação Geral`, 9 outros | 6.099, quase todos `Produto` |
| Detrator ou neutro sem texto | 5.287 (3.130 + 2.157), todos `Não é possível determinar` | 4.744 |
| NPS com texto | 5.722 (2.397 indeterminados, 3.325 classificados) | 5.220 |

Leitura: o padrão se confirma em prod. O NPS sem texto é cerca de 7 em cada 10 itens, e o resultado do LLM é função da nota. A diferença é o macrotema atribuído aos promotores sem texto: `Relacionamento com a Conta Azul` em prod e `Produto` no dev, o que mostra que o prompt do dev já difere do de prod. Em prod, promotores sem texto inflam `Relacionamento com a Conta Azul`.

---

## 3. Mapeamento: reunião → evidência no dev → decisão de arquitetura

| Tema da reunião | O que o dev mostra | Decisão de desenho |
|---|---|---|
| **Desacoplar modelo de dados e classificação** (André; full refresh de até R$3 mil) | Só `category_gemini` varia no item; o resto do que o LLM devolve é por item; `full_prompt` é gravado em cada linha e acopla dado e prompt | Duas tabelas: `voc_interaction` (dado, sem LLM) e `voc_extraction` (LLM, memoizada por conteúdo, prompt e modelo). Mexer em coluna de dado nunca reclassifica |
| **Feature flag** (André) | Os experimentos de setembro já rodam um prompt novo ao lado do vigente, em tabelas à parte | `voc_prompt_version` com versão ativa e versão em shadow. A extração nova grava ao lado e só vira vigente quando o eval passa |
| **VOC genérica + especialistas, ou só colunas** (Talitha × Philipi) | Os atributos específicos por fonte são poucos e estreitos (NPS: nota e campanha; aquisição: motivo/submotivo; Zendesk: tipo, subcategoria, transcrição) | Core com colunas tipadas e comuns. Especialista nasce como **view** sobre o core; só vira tabela quando tem **extração própria** (ex.: cluster do Suporte). Isso responde às duas posições sem custo de LLM extra |
| **Gemini absorve o entendimento dos agentes** (Philipi) | O `resumo_do_incidente_gemini` e a saída nova já existem em `voc_prompt_v2_result` | O schema de saída da extração passa a incluir `problema_canonico`, natureza e sentimento em enum. O agente especialista lê contagens e exemplos, não reclassifica |
| **Amostra de 30%** | A dim já cobre 100% dos itens das 6 fontes; a amostragem está no agente | Os agentes passam a ler agregados (SQL) e exemplos por cluster. A amostra deixa de ser da população e passa a ser da evidência dentro do cluster, o que também resolve a janela de contexto |
| **Redundância Intercom × VOC** | `source` não tem Intercom no dev | Incluir o Intercom como fonte do core; só então os agentes param de ler direto |
| **Logs do Notion para o Datalake** | Sem tabela de log de execução no dev | `voc_run_log` e log dos agentes no Datalake, seguindo a esteira do Nexus; o Notion vira só a visualização |
| **Custo** (US$5/dia como gatilho) | 22% dos itens da janela são NPS sem texto e dispensam LLM | Regra T0 antes do LLM e teto de itens por run (`max_llm_items`) |

---

## 4. Rearquitetura proposta (to-be)

```
staging (1 por fonte, PII redigida, BRT, content_hash)
   │  inclui Intercom como fonte nova
   ▼
silver_voc.voc_interaction          dado do item. Sem LLM. PK nk_voc_id. MERGE por content_hash
silver_voc.voc_interaction_text     texto cru (policy tag). transcription, reason, problem_details, meetrox_summary
silver_voc.voc_prompt_version       versão do prompt (substitui full_prompt por linha). Flag ativa / shadow
silver_voc.voc_extraction           saída do LLM por (item, conteúdo, prompt, modelo). extraction_status explícito
silver_voc.voc_extraction_category  ponte item × categoria (is_primary)
silver_voc.voc_run_log              1 linha por run e fonte. Substitui o log no Notion
   ▼
gold_voc.fact_voc_interaction       1 linha por item, extração vigente. É a "VOC centralizada"
gold_voc.fact_voc_interaction_category
gold_voc.dim_voc_category           taxonomia versionada (258 rótulos hoje no teste)
   ▼
serving_voc.voc_nps_v1 | voc_suporte_v1 | voc_negocio_v1 | ...   views sobre o core; tabela só com extração própria
gold_strategy.dim_voc_full_category   view de compatibilidade (21 colunas, grão antigo) com prazo e dono
```

### 4.1 O que muda nas colunas atuais

| Coluna (24 no dev) | Destino |
|---|---|
| `source`, `id_ferramenta`, `nk_company_id`, `nk_accountancy_id`, `nk_event_date` | `fact_voc_interaction` (`nk_voc_id` como chave; `id_ferramenta` mantida como legado) |
| `macro_theme`, `sentiment`, `incident_type_gemini`, `incident_summary_gemini`, `domain`, `subdomain` | `voc_extraction`, expostas no fact. `sentiment` vira enum; `domain` e `subdomain` atômicos |
| `category_gemini` | `voc_extraction_category` (ponte) |
| `llm_send_status` | `extraction_status`: `ok`, `sem_texto`, `regra_nps`, `indeterminado`, `api_error`, `invalid_label` |
| `reason`, `sub_reason`, `problem_details`, `transcription`, `meetrox_summary` | `voc_interaction_text` (restrita) |
| `category`, `ticket_subcategory`, `ticket_type`, `incident_url` | especialista Suporte (atributos de origem do ticket); `category` de NPS (Promotor/Neutro/Detrator) fica em `fact_nps_survey` |
| `full_prompt` | `voc_prompt_version` |
| `is_atendimento` | derivada de `source` (na view), sai da tabela |

### 4.2 Regras antes do LLM (T0)

1. **NPS sem texto:** `extraction_status = 'regra_nps'`, `macro_theme` nulo e categoria nula. A nota (Promotor, Neutro, Detrator) continua disponível no fact de NPS. Evita 10.843 chamadas (22% dos itens da janela) e remove o `Produto` artificial.
2. **Texto sem informação** ("NADA A FALAR", "10", "nada"): lista de padrões para `sem_texto`, avaliada contra os 2.408 casos com texto indeterminado.
3. **Memoização por conteúdo:** mesma chave de conteúdo, prompt e modelo não chama o LLM de novo (já detalhada em `arquitetura-tabelas-voc-dataform.md`).

### 4.3 Compatibilidade

A view `gold_strategy.dim_voc_full_category` mantém as 21 colunas e o grão item × categoria, para Looker, Metabase, Sheets e MCP, com prazo de desligamento de 90 dias e dono. O Erick pode manter `domain` e `subdomain` como colunas extras da view.

---

## 5. Pontos que precisam de confirmação

| # | Ponto | Por que importa | Quem confirma |
|---|---|---|---|
| 1 | O Intercom "já alimenta o VOC": qual VOC? | Confirmado em dev e prod: a dim não tem `source = 'intercom'`. Se existe outra tabela, o desenho muda | Philipi e Erick |
| 2 | Como o Erick deriva `domain`/`subdomain` e por que há valores com `|` | Define se o domínio entra no core ou na extração, e como fica atômico | Erick |
| 3 | `domain`, `subdomain` e `is_atendimento` ainda não estão em prod (21 colunas) | São mudança do Erick só no dev; falta saber se vão para prod e com qual regra | Erick |
| 4 | O NPS "sem texto = só nota" vale em prod? | Confirmado (69,3% em 90 dias). Mudou só o macrotema dos promotores (`Relacionamento com a Conta Azul` em prod, `Produto` no dev) | — |
| 5 | Acesso do MCP ao `contaazul-datalake-dev` | Hoje só o console funciona; para automatizar as medições é preciso a permissão `mcp.tools.call` | Quem administra o projeto |
| 6 | Código do Erick e dos experimentos de setembro | Só vi tabelas e resultados. Falta o SQL para dizer o que reaproveitar | Erick |

---

## Apêndice — Consultas usadas (console do BigQuery, dev, somente leitura)

Todas sobre `contaazul-datalake-dev.gold_strategy_dev_ericklemos.dim_voc_full_category`, exceto a última.

| Consulta | Objetivo |
|---|---|
| `INFORMATION_SCHEMA.TABLES` do dev com `LOWER(table_name) LIKE '%voc%'` | Localizar as tabelas de VOC (24 resultados) |
| `INFORMATION_SCHEMA.COLUMNS` | 24 colunas, `nk_event_date` como coluna de partição, sem clustering |
| `GROUP BY source` com contagens | Volume, itens, categorias e indeterminados por fonte |
| `GROUP BY source, domain, subdomain` | Distribuição de domínio e subdomínio |
| CTE por `(source, id_ferramenta)` com `COUNT(DISTINCT col)` por coluna | Quais colunas variam dentro do item |
| `AVG(LENGTH(col))` e `COUNT(DISTINCT ...)` | Largura e cardinalidade de `full_prompt`, texto, sentimento, macrotema |
| NPS e aquisição por `macro_theme` indeterminado, `reason` vazio e `llm_send_status` | Hipótese do NPS sem comentário |
| `dataform.INFORMATION_SCHEMA.COLUMNS` com `__TABLES__` (`LIKE 'voc%'`) | Colunas e contagem de linhas dos experimentos |
| `dataform.voc_subteste_final` agrupado por `source` | Tamanho do `facts` e categorias por fonte |
