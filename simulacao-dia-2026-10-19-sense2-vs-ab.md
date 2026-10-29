# Simulação de um dia completo (seg 19/10/2026): Sense 2.0 (agente de Suporte) × população inteira com A + B

28/10/2026. Complementa `resultados-teste-prompt-suporte-gemini.md`. Script para o dev: `simulacao_dia_suporte_2026-10-19.sql`.

## 1. O que foi pedido e o que foi possível

Pedido: simular a existência de `domain`, `subdomain` e `is_atendimento` na `dim_voc`, com a população inteira de um dia, e comparar o que o Sense 2.0 cobre hoje (foco no agente de Suporte) com o enriquecimento que A + B traria.

| Parte | Status |
|---|---|
| Dia completo do Sense 2.0 (Suporte V2) | Feito. Log da execução de 20/10 no Notion (dados de 19/10) |
| População inteira do dia em `dim_voc_full_category` (prod) e ponte com as conversas do Intercom | Feito, medido no BigQuery (`contaazul-ssbi`) |
| Colunas `domain`, `subdomain`, `is_atendimento` | Na prod elas não existem (21 colunas). Simuladas com o mapa categoria → domínio derivado da cópia do Erick no dev (seção 11) |
| Chamada B (natureza, problema canônico) na população do dia | **Executada por você no dev em 28/10**, nos 1.215 tickets (resultados na seção 11). O MCP não tem acesso ao dev; eu escrevi o script e analisei os resultados colados |

## 2. O dia escolhido

Segunda 19/10/2026. É o dia da execução `Suporte V2 · 2026-10-20 04:04` (modo live, status OK, cobertura 100%), com custo, tokens e duração registrados. Tem mais de 8 dias de maturação na `dim_voc`, que continua mudando por cerca de 8 dias depois do dia.

## 3. O que o Sense 2.0 (Suporte V2) fez nesse dia

Fonte: log da execução no Notion.

| Etapa | Conversas |
|---|---|
| Universo (conversas do Intercom criadas em 19/10) | 2.728 |
| Selecionadas | 934 (34,2%): censo N2/N3 102 + censo muito negativo 38 + amostra de 30% com 794 (peso ×3,333) |
| Pré-filtradas vazias | 229 |
| Classificadas | 705 (25,8% do universo) |
| Em 130 sinais ativos (121 existentes + 9 novos) | 591 |
| Abaixo do piso (cluster novo exige 3 ou mais conversas) | 114 |
| Escaladas / resolvidas no chat | 1.120 (41,06%) / 883 (32,37%) |

Custo e tempo: US$ 1,49, 225 mil tokens estimados, 1.500 s, 700 chamadas de ferramenta.

Conferi o universo: `ingestion_intercom_conversations` tem exatamente 2.728 conversas criadas em 19/10. O universo do V2 é a base do Intercom, não o Zendesk.

## 4. A população inteira do dia e a ponte

**Conversas do Intercom (universo do V2):** 2.728. Com resumo de IA: 1.961 (71,9%). Retidas pelo bot: 1.707 (62,6%). Transbordadas: 917 (33,6%). Sem tipo: 104.

**Tickets na `dim_voc_full_category` (Zendesk, 19/10):** 1.215 (1.349 linhas, porque a categoria explode a linha). Todos enviados ao LLM, 1.017 (83,7%) com transcrição.

Para ligar as duas bases usei `zendesk_concatened_messages`, que tem `ticket_id` e `intercom_conversation_id` na mesma linha.

| Origem dos 1.215 tickets | Tickets | % | N2/N3 |
|---|---|---|---|
| Vieram de uma conversa do Intercom | 824 | 67,8% | 99 |
| Web/e-mail (offline) | 185 | 15,2% | 52 |
| Sem conversa registrada | 197 | 16,2% | 14 |
| Chat nativo do Zendesk, sem Intercom | 9 | 0,7% | 0 |

- **A interseção:** das 2.728 conversas, 824 (30,2%) têm ticket na dim. Das 917 transbordadas, 781 (85,2%) viraram ticket na dim; das 1.707 retidas, 43 (2,5%).
- **Validação cruzada:** os N2/N3 que vêm do Intercom são 99, contra 102 do censo N2/N3 do V2. A ponte reproduz o recorte do agente.
- **Nível do ticket:** Dúvida (N1) 1.034, Ajustes (N2) 153, Melhoria 16, Incidente (N3) 12.

## 5. Cobertura: o que cada lado vê

| | Sense 2.0 (Suporte V2) | A + B (tickets Zendesk) |
|---|---|---|
| Base | Conversas do Intercom | Tickets do Zendesk |
| Tamanho do dia | 2.728 | 1.215 |
| Observados um a um | 705 (25,8%) | 1.215 tickets com B, dos quais 1.017 (83,7%) com transcrição |
| Tickets da interseção (824) vistos individualmente | Cerca de 317 (38%), estimativa: censo N2/N3 + 30% do resto | 824 |
| Tickets fora do Intercom (391) | 0 | 391, dos quais 66 N2/N3 |
| N2/N3 do dia | ~102 (censo, só Intercom) | 165 (+62%) |
| Conversas retidas pelo bot (1.664 sem ticket na dim) | Vê por amostra (1.071 retidas com resumo) | Não vê |
| Taxa de escala e resolução no chat | Calcula (41,06% / 32,37%) | Não calcula |

Leitura:

- O censo N2/N3 do V2 deixa de fora 66 dos 165 N2/N3 do dia (40%), porque eles não entram pelo Intercom.
- Em contrapartida, A + B não enxerga as ~1.900 conversas do Intercom sem ticket na dim (70% do universo do V2), a maioria resolvida pelo bot.
- Os dois lados são complementares na interseção de 824 tickets.

## 6. As colunas `domain`, `subdomain` e `is_atendimento`: simulação

**Como estão no dev (copia do Erick, investigação de 27/10):**

- `domain` e `subdomain` vêm sem regra de derivação conhecida. Há valores concatenados com `|` (ex.: `Financial | Core Accounting & Analytics`), e no Zendesk 499 de 27.787 itens (1,8%) estavam sem domínio.
- `is_atendimento` é `true` em todo o Zendesk e `false` nas demais fontes. Para os 1.215 tickets do dia ele valeria `true` em 100% e não separa nada.

**Proxy de `is_atendimento` por categoria** (Transbordo, Tempo de atendimento/espera, Suporte Geral, Chat, Telefonico, Geral; lista minha, a validar):

| | Tickets | % |
|---|---|---|
| Com pelo menos uma categoria de atendimento | 87 | 7,2% |
| Somente categorias de atendimento | 72 | 5,9% |
| Desses 87, vindos do Intercom | 67 | — |

**Proxy de domínio (prefixo da categoria).** Não é o DDD; serve para dimensionar. Tickets distintos por família, com os que vêm do Intercom entre parênteses:

| Família | Tickets |
|---|---|
| Emissão | 288 (202) |
| Faturamento do Plano / NF ContaAzul | 181 (122) |
| Extrato/Conciliação/Integração | 163 (112) |
| Problemas de acesso, login, dois fatores, MFA | 64 (45) |
| Gestão de Licenças / Lote do Parceiro | 62 (32) |
| Conta PJ | 60 (34) |
| Cobrança | 39 (24) |
| Compras | 36 (21) |

Um ticket pode estar em mais de uma família. A maior categoria isolada é `Emissão - NFS-e - Outras Melhorias`, com 213 tickets.

O mapa real categoria → domínio/subdomínio sai do script, a partir da cópia do Erick (consulta R3).

## 7. O que A + B enriquece, ponto a ponto

| Capacidade | Sense 2.0 hoje | Com A + B | Evidência |
|---|---|---|---|
| Granularidade da análise | Cluster (130 sinais ativos) | Ticket (1.215) | Medido |
| Natureza (bug, gap, dúvida...) | Por sinal (agregado); não guarda por ticket | Por ticket, na chamada B | Medido no dia completo (seção 11.2); sem rótulo humano |
| Problema em texto | Cluster nomeado, granular, em catálogo vivo (252 sinais) | Texto livre por ticket, que exige agrupamento por embeddings | Dia completo: 507 textos distintos em 530 tickets de bug, gap e usabilidade (seção 11.3) |
| Domínio e subdomínio | Por sinal (DDD, de baixo para cima) | Por ticket, via mapa da categoria | Medido: o mapa cobre 99,0% das categorias-ticket (seção 11.4) |
| `is_atendimento` | Natureza `operacional`/`ruído` segregada por sinal | Por ticket (proxy de 87 tickets, ou natureza `operacional`/`ruído` da B, 123 tickets) | Medido (seção 11.5) |
| Cobertura de tickets | 38% dos tickets da interseção, 0% dos 391 fora do Intercom | 100% | Medido (38% é estimativa) |
| N2/N3 | ~102 | 165 | Medido |
| Persistência | Contagens no Notion; ticket e vínculo com cluster não gravados | Ticket e classificação no BigQuery | Doc |
| Tendência, score, leitura, escala e resolução | Sim | Não | Doc |
| Conversas retidas pelo bot | Sim (por amostra) | Não | Medido |

## 8. Custo e tempo do dia

| | Sense 2.0 (V2) | A + B |
|---|---|---|
| Custo do dia | US$ 1,49 (225 mil tokens estimados, a 6,6e-6 US$/token) | A já roda em produção; B para 1.215 tickets ≈ US$ 0,55 (1,8 milhão de tokens de entrada) |
| Tempo | 1.500 s (25 min); outras execuções vão de 952 a 1.500 s | Não medido |

- Os tokens do V2 (Claude) e do Gemini não são comparáveis um a um: o Gemini custa US$ 0,25 por milhão de entrada, e a estimativa do V2 usa uma taxa mista de US$ 6,6 por milhão.
- Para a B, a duração depende da vazão do `us.vertex_connection`: com 2, 5 ou 20 chamadas por segundo, 1.215 chamadas levam cerca de 10, 4 ou 1 minuto (hipótese de vazão, não medida).
- O custo do V2 cobre tudo que o agente faz (clusterização, síntese de 50 sinais, leitura e escrita no Notion), não só a classificação.

## 9. O que foi rodado

Rodado por você no dev em 28/10 (`simulacao_dia_suporte_2026-10-19.sql`: 3 tabelas temporárias com 7 dias de validade e 6 consultas). O que cada consulta fechou:

| Consulta | Fecha o quê |
|---|---|
| R1 | Cobertura V2 × A + B |
| R2 | Ponte por origem e por tipo de interação |
| R3 | Domínio/subdomínio: cobertura do mapa do Erick, domínios compostos e distribuição |
| R4 | `is_atendimento`: regra do dev × proxy × natureza da B |
| R5 | Natureza por origem e nível (N1/N2/N3), problema canônico e descoberta preenchidos |
| R6 | Natureza × domínio e textos distintos de problema |

Resultados na seção 11.

## 10. Limites

- **Dev sem acesso do MCP.** As tabelas do dev foram criadas e consultadas por você; eu só vi os resultados colados.
- **Natureza e problema canônico sem rótulo humano.** Os resultados da seção 11 mostram o que a B devolve, não se está certo.
- **Detalhe por sinal não recuperável.** O Notion sobrescreve os sinais a cada execução, então só tenho os agregados do log de 19/10.
- **Ponte aproximada.** Liga ticket e conversa por `zendesk_concatened_messages`. Das 963 conversas com ticket, 824 estão na dim no período de 1 a 27/10; as outras 139 podem ter data de evento fora da janela ou ausência na dim, e eu não verifiquei qual.
- **Os 38% de visibilidade do V2 sobre a interseção** são estimativa (censo + 30% do resto), não medição.
- **Proxies.** O de `is_atendimento` usa uma lista de categorias minha, e o de domínio é prefixo de nome, não DDD.
- **Um único dia.** Segunda-feira, que tem volume acima da média (as médias do Zendesk são ~830 tickets por dia).

## 11. Resultados da execução no dev (R1 a R6)

Totais calculados a partir das linhas coladas (R5 e R6), somando as linhas na mão; arredondamentos em uma casa.

### 11.1 Cobertura e ponte (R1, R2)

- **A + B observou 1.215 tickets, 1.017 deles com transcrição (83,7%).** Os 198 sem transcrição são 197 tickets sem linha em `zendesk_concatened_messages` e 1 web/e-mail. Para esses a B só tinha motivo, submotivo e metadados.
- **N2/N3:** 165 tickets, contra 102 do censo do V2 (+62%). Pela origem: 98 + 1 do Intercom, 52 web/e-mail, 14 sem conversa. 66 (40%) ficam fora do alcance do V2.
- **Ponte:** 781 tickets de conversa transbordada e 43 de conversa retida vêm do Intercom (824, 67,8%). Todos os 824 têm transcrição.
- **JSON da B:** válido nos 1.215 tickets (0 inválidos em R5).

### 11.2 Natureza (R5)

| Natureza | Tickets | % do dia | Dúvida N1 | N2/N3 | Do Intercom | Fora do Intercom |
|---|---|---|---|---|---|---|
| bug | 314 | 25,8% | 229 | 84 | 222 | 92 |
| dúvida | 253 | 20,8% | 246 | 6 | 172 | 81 |
| comercial | 243 | 20,0% | 209 | 34 | 165 | 78 |
| gap | 113 | 9,3% | 83 | 18 | 63 | 50 |
| usabilidade | 113 | 9,3% | 109 | 3 | 76 | 37 |
| operacional | 77 | 6,3% | 63 | 13 | 57 | 20 |
| infra | 56 | 4,6% | 50 | 6 | 35 | 21 |
| ruído | 46 | 3,8% | 45 | 1 | 34 | 12 |

A coluna "Dúvida N1" é o `ticket_type` = Dúvida (1.034 tickets); a soma das colunas de nível não fecha com o total porque 16 tickets são `Melhoria`.

Três leituras:

- **Sinal de produto escondido no N1.** Dos 314 tickets que a B marca como bug, 229 (73%) estão como Dúvida (N1) no Zendesk; só 84 são N2/N3. Do N1, 22% saem como bug. O censo do V2 se baseia em N2/N3.
- **Peso de não-produto.** Comercial, operacional e ruído somam 366 tickets (30,1% do dia). Entre os 165 N2/N3, 34 (21%) são comerciais.
- **Campos auxiliares seguem a regra, com poucas falhas.** Dos 253 tickets de dúvida, 236 (93%) trazem `descoberta_feature`. Nenhum bug tem `descoberta_feature`. Dois bugs e dois de usabilidade vieram sem `problema_canonico`, e 13 tickets de `infra` trouxeram texto, que a regra reserva a bug, gap e usabilidade.

### 11.3 Problema canônico (R5, R6)

- 549 tickets (45,2%) têm `problema_canonico`: 312 bug, 113 gap, 111 usabilidade e 13 infra.
- Dentro do mesmo domínio e natureza, em bug, gap e usabilidade, as linhas de R6 (a consulta tinha `LIMIT 60` e devolveu 60 linhas, ou seja, as 60 maiores combinações) somam 530 dos 540 tickets dessas três naturezas e 507 textos distintos (96%). Exemplos: Tax & Compliance bug com 156 tickets e 138 textos; Financial bug com 70 e 69.
- Como referência de escala, o V2 pôs 591 conversas em 130 sinais (cerca de 4,5 por sinal) nesse dia. Com ~507 textos distintos, a B ainda precisa de uma etapa de agrupamento para chegar à granularidade de um cluster.

### 11.4 Domínio e subdomínio simulados (R3)

- O mapa categoria → domínio, derivado dos itens de categoria única da cópia do Erick, cobre 1.335 das 1.349 categorias-ticket (99,0%). 14 ficam sem domínio e 10 (0,7%) vêm compostas com `|`.
- Tickets distintos por domínio (um ticket pode contar em mais de um): Tax & Compliance 331, Monetization 258, Financial 201, Banking & Cash 99, Cross Platform 95, Identity 95, Partnership 67, Core Accounting & Analytics 37, Master Data 26, Order-to-Cash 26, Developer Platform 16, Supply Chain 15.
- As maiores combinações domínio × natureza (R6, domínio pela primeira categoria): Monetization × comercial 210, Tax & Compliance × bug 156, Tax & Compliance × dúvida 71, Financial × bug 70, Financial × dúvida 59, Tax & Compliance × gap 45, Financial × usabilidade 43, Identity × infra 39 e Cross Platform × operacional 36.

### 11.5 `is_atendimento` (R4)

| Definição | Tickets |
|---|---|
| Regra do dev (`true` em todo o Zendesk) | 1.215 |
| Proxy: tem categoria de atendimento | 87 |
| Chamada B: natureza `operacional` ou `ruído` | 123 |
| Os dois critérios ao mesmo tempo | 65 |

Dos 87 do proxy, 65 (75%) saem como operacional/ruído na B; dos 123 da B, 65 (53%) estão no proxy. Os critérios se sobrepõem, mas não são equivalentes, e a regra do dev não separa nada.

### 11.6 O que isso muda na comparação com o Sense 2.0

- **Cobertura:** o dia inteiro de tickets fica estruturado (1.215), inclusive 391 que o V2 não vê.
- **Seleção por nível:** se a natureza da B se confirmar em amostra rotulada, o censo por N2/N3 captura só 27% dos bugs do dia (84 de 314) e inclui 34 tickets comerciais.
- **O que o agente continua fazendo:** agrupar os textos em problemas nomeados, tendência, escala e resolução, e as conversas retidas pelo bot. Nenhuma dessas partes foi coberta pela B.

### 11.7 Ressalvas e verificações pendentes

1. **Natureza sem validação humana.** No teste de 33 tickets a B marcou como bug casos em que o produto funciona como desenhado. Os 229 bugs em tickets N1 (e os 13 tickets de `infra` com texto) precisam de uma amostra lida por humanos antes de qualquer conclusão sobre o censo.
2. **198 tickets sem transcrição.** A natureza deles vem só de metadados. Convém ver a distribuição separada (consulta sugerida: R5 filtrando `tem_transcricao = FALSE`).
3. **Domínio é da categoria, não do item.** Foi atribuído pela primeira categoria do ticket (R6), e o mapa vem da cópia do Erick, cuja regra de derivação não conheço.
4. **Duração e custo da B no dev.** Você não passou o tempo nem os tokens do job. A estimativa de custo (US$ 0,55) continua sem medição.
5. **Um único dia.**
