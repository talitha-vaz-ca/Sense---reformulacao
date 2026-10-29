# Plano de testes: Gemini 3.1 flash-lite como LLM auxiliar antes dos agentes especialistas

29/10/2026. Escopo: os 4 especialistas e o Cross que a [Sense — Central](https://app.notion.com/p/3a34a554a42f8118ae36fe0582381266) lista como "no ar hoje". O Suporte V2 entra como **controle**, porque já tem um LLM auxiliar na frente (o `ai_issue_summary`, gerado pelo Gemini fora do agente). Complementa `justificativa-design-agente-suporte-v2.md`.

Nada aqui foi executado em `AI.GENERATE`: o MCP de BigQuery não tem acesso ao dev nem a essa função. O que rodei foram consultas de leitura em prod para medir volumes e validar as seleções (números na seção 2). Os três scripts SQL estão prontos para você rodar no console do BigQuery, em `contaazul-datalake-dev`.

## 1. Hipótese e desenho

**Hipótese.** Um LLM barato na camada de dados, antes do agente, pode assumir o trabalho *por item* (extrair campos, casar com um catálogo fechado) e deixar para o Claude só o que exige julgamento: nomear o que é novo, consolidar, sintetizar a `Leitura`.

**Por que vale testar.** No Suporte, o custo está no raciocínio do Claude e não no tamanho do texto (~589k dos ~690k tokens da 1ª run prod vieram das duas chamadas de Agent, segundo o prompt `:438`). Mas essa premissa **não vale igual** para os outros agentes (seção 2), por isso o teste é por agente, com hipótese própria.

**Três estágios, o mesmo em todos:**

| Estágio | O que acontece | Onde roda |
|---|---|---|
| 0. Amostra | Seleção determinística do dia ou mês, reproduzindo a regra do agente | BigQuery (dev) |
| 1. LLM auxiliar | Gemini 3.1 flash-lite via `AI.GENERATE`, `thinking_budget 0`, temperatura 0, `responseMimeType application/json`, **sem `output_schema`** (com ele, 17 de 66 chamadas falharam no teste anterior) | BigQuery (dev) |
| 2. Especialista | O passo do agente que hoje faz o trabalho por item, com a entrada reduzida | Só na fase 2 (seção 6) |

**Variantes de entrada** (valem para qualquer agente):

| Código | O que o auxiliar entrega | Papel do Claude depois |
|---|---|---|
| P0 | Nada (controle: como é hoje) | Tudo |
| P1 | Campos extraídos por item, sem catálogo (assunto, natureza, grão) | Agrupar, casar, nomear |
| P2 | Id do item do catálogo fechado, ou "sem match" + rascunho | Só o "sem match", a consolidação e a `Leitura` |

**Princípios herdados do design (seção 6 da justificativa):** o auxiliar fica na camada de dados, nunca dentro da sessão do agente (um agente = um modelo); não substitui a `Leitura` nem o `message_body`; PII redigida antes de qualquer LLM; nada em prod; tabelas só em `contaazul-datalake-dev` com expiração de 7 dias.

**Direção do erro.** A V2.5 mostrou que o Haiku "erra pro lado NOVO em vez de forçar match errado". Para o Gemini, medimos isso: *falso NEW* (inofensivo, o Claude ainda vê o item) contra *match errado* (esconde um problema distinto). O segundo é o que reprova.

## 2. Mapa dos agentes (o que mede onde está o ganho)

Volumes e tamanhos de texto foram medidos hoje por leitura no BigQuery e no Notion (prod). As regras dos agentes (colunas "onde está o custo" e "regras que limitam") vêm da leitura dos MDs de `routines/prod/` feita por um subagente, com `arquivo:linha`; eu não reli cada linha citada.

| | Suporte V2 (controle) | pNPS | Portal de Ideias | Onboarding | Cross |
|---|---|---|---|---|---|
| **Cadência (Central)** | Diário 04:00 | Quinzenal + fechamento mensal | Mensal, dia 1 | Diário 9:00 | Mensal, dia 3 |
| **Texto cru** | `ai_issue_summary`: 161 chars em média (707 selecionadas em 19/10, de 2.728) | `nps_comment`: 72 chars em média, p90 170 | `title` 66 + `body` 373 chars (p90 652) | Transcrição MeetRox: 70 a 135 mil chars (17 a 34 mil tokens) por reunião | Não lê texto cru (`Descrição` de 1 frase; `Leitura` só nos surfaced) |
| **Volume** | 707 conversas/dia | 334 comentários em set/26 (189 em out até o dia 28) | 33 a 52 ideias novas/mês | ~30 a 50 reuniões com substância/dia | ~630 sinais no cold start |
| **Onde está o custo** | Raciocínio do Claude: ~353k (classificar) + ~236k (reconciliar) de ~690k tokens na 1ª run; média de ~358k/run nos logs | **Método, não tokens**: CASE/REGEXP desenhados pelo LLM + auditoria de resíduo; a run 2 levou 34 min e truncou ~9 de 27 sinais | Backfill único (~4M tokens); o delta mensal é pequeno | Massa de entrada: 10 a 36M tokens/mês (estimativa do subagente) | Cold start ~1,1M tokens (~US$ 7); regime estável "dezenas de k" |
| **Verdade disponível** | Por **sinal**: `Menções` de 19/10 na DB de Sinais | Por **sinal**: DB de Sinais set/26, 28 sinais, 408 menções | **Por ideia**: `cluster_map` (id → cluster, tema) para 10.160 ideias em 1.764 clusters | Por sinal (contagem diária); sem texto no BigQuery | Por OP (back-links com sinais), exige export do Notion |
| **Regras que limitam o auxiliar** | Seleção por metadado; sem regex; `Leitura` do `message_body` | Contagem "determinística e reprodutível" (`nps:408`); BQ só leitura; registro por comentário só em memória | Reusar os prompts do backfill (drift contra os 1.610 clusters); seed congelado | **I5**: resumo nunca vira sinal; "comprimir e ler tudo rápido não é opção"; `prova_de_leitura` exige a transcrição íntegra; PII redigida antes de qualquer modelo | "Nunca reabre a fonte crua"; fingerprint de delta = Descrição + Leitura + Cru |
| **Prioridade do teste** | 1 (script pronto) | 2 (script pronto) | 3 (script pronto) | 4 (protocolo; depende de decisão) | 5 (opcional) |

Outras fontes úteis do `dim_voc_full_category` nos últimos 7 dias (21 a 27/10): Zendesk 832 itens/dia (4.042 chars de contexto), NPS 60/dia (44 chars), aquisição 76/dia, Keys-Off 28/dia, Portal de Ideias ~1/dia.

**Catálogo do Suporte V2 hoje:** 273 sinais, 268 ativos em outubro, 228 nos últimos 7 dias; `Descrição` média de 112 chars, `Leitura` média de 506 chars.

**Achado que muda o desenho.** O texto de entrada do pNPS e do Suporte é minúsculo. Ali o ganho de um auxiliar **não é redução de tokens do Claude**, é qualidade, estabilidade e tempo. O ganho de tokens só é plausível no Onboarding (transcrições longas), que é justamente o agente mais restrito pelas regras.

## 3. Fichas de teste

### AUX-S · Suporte V2 (controle) · `teste_aux_gemini_suporte_catalogo.sql`

- **Pergunta.** O Gemini reproduz o ranking de sinais do dia que o Claude produziu, casando cada conversa com o catálogo?
- **Entrada.** A seleção da V2 reproduzida em SQL para 19/10: censo N2/N3 (106) + censo "Muito negativo" (37) + amostra 30% por hash (564) = **707** conversas (a V2 documentou ~705), peso total 2.023 menções escaladas. Validado em prod (consulta de leitura).
- **P1.** Extração por item (ruído, grão fricção/descoberta, assunto, natureza). Entrada de ~250 tokens por chamada.
- **P2.** Casamento com catálogo fechado de 146 nomes com ids (100 de maior `Menções` em 19/10 + 46 de maior Score como distratores), saída `match_id`/`assunto_rascunho`.
- **Verdade.** `Menções` por sinal em 19/10 (DB de Sinais V2 prod). **Não há verdade por conversa**: a V2 não persiste conversa→sinal.
- **Métricas.** R3: Spearman e Pearson do ranking, top-10 e top-20 em comum, erro relativo no top-30. R2: cobertura (casadas, sem match, ruído) por balde. R4: o que sobra sem match (trabalho que ainda é do Claude). R6: autoconsistência com 2 repetições. R8: 40 itens para rótulo humano.
- **Custo estimado.** P2 ≈ 707 chamadas × ~3 mil tokens ≈ 2,1M tokens ≈ **US$ 0,55/dia** com nomes (~US$ 0,85 com os 273; ~US$ 1,9 se cada item levar a `Descrição`). P1 ≈ US$ 0,05/dia. Comparável ao ~US$ 2,4/run médio de Claude (logs), e só vira economia se a fase 2 mostrar que o Claude gasta bem menos.
- **Limites.** Catálogo reduzido (146 de 273; os 100 "de maior menção" favorecem o Gemini, por isso os distratores). O piso ≥3 e a consolidação da V2 não são aplicados.

### AUX-N · pNPS · `teste_aux_gemini_pnps.sql`

- **Pergunta.** O Gemini rotula cada comentário nos baldes N1/N2 de modo que as contagens batam com as do agente, dispensando o desenho de regex e a auditoria de resíduo?
- **Por que muda de natureza.** Os comentários são tão curtos (~6 mil tokens por mês no total) que o Claude poderia lê-los todos. A dor do agente é método e tempo. A tabela por comentário também é a "DB de Comentários" que o MD lista como evolução futura (`nps:341`).
- **Entrada.** pNPS + Survicate de set/26: **334 comentários** (validado em prod).
- **Saída.** `n1[]`, `n2[]` (até 2, lista fechada), `cenario` (livre, ≤6 palavras), `valencia`, `superficie`.
- **Verdade.** N2 e N1 somados dos 28 sinais de set/26 (408 menções, multi-rótulo, ~1,2 rótulos por comentário). Já embutida no script.
- **Métricas.** R2/R2b: contagem por N2 contra o agente, Pearson, Spearman, top-5, erro relativo nos N2 ≥10. R3: N1. R5: cenários nomeados dentro de "Bugs & instabilidade" e "Recursos faltando" (o que o agente abriria em N3: Emissão de NF com falhas 16, Conciliação bancária falha 15, Falhas e limitações de integração 13, Faltam relatórios 14…). R6: autoconsistência. R7: 50 comentários para rótulo humano.
- **Custo.** ~342 chamadas × ~1,3 mil tokens ≈ 0,45M tokens ≈ **US$ 0,11 por rodada**, ~US$ 0,3 por mês.
- **Pendência antes de rodar.** O schema do agente tem **16 N2**; o script lista os 13 vistos em set/26 + `Risco de churn (flag)`. Complete a lista na linha marcada `###`.
- **Regra a decidir.** O MD diz que a contagem é "determinística e reprodutível". Um rótulo de LLM com temperatura 0 é reproduzível, mas não é regra fixa. A decisão é do dono do agente.

### AUX-P · Portal de Ideias · `teste_aux_gemini_portal_ideias.sql`

- **Pergunta.** Dado o catálogo congelado, o Gemini escolhe o mesmo tema e o mesmo cluster que o backfill?
- **Por que é o teste mais forte.** É o único agente com rótulo **por item**: `sense_ideas_portal_cluster_map` (10.160 linhas) e `cluster_meta` (1.764 clusters com `titulo_canonico`).
- **Entrada.** Amostra estável de ~4% das ideias (~400).
- **T1.** Tema (lista fechada de ~17). **T2.** Cluster dentro do tema, com o tema verdadeiro ("oráculo"), isolando a capacidade de casar. **T3.** O mesmo com o tema predito por T1 (pipeline completo).
- **Simulação de "ideia nova contra catálogo congelado".** O catálogo exclui clusters de tamanho 1 e a resposta certa para ideias desses clusters é `NEW`. Sem isso, o catálogo conteria o próprio item e o teste seria enviesado.
- **Métricas.** R2: acurácia do tema. R3: acurácia do cluster (tamanho ≥2), falso NEW, NEW correto. R4: 30 erros lado a lado com os dois títulos canônicos para julgamento humano. R5: acurácia por faixa de tamanho de cluster. R6: tamanho do catálogo por tema e custo.
- **Custo.** US$ 1 a 2 na amostra de 400. Em produção, ~40 ideias/mês ≈ centavos. Reprocessar todo o backfill (10 mil × ~3 mil tokens ≈ 30M tokens) ≈ US$ 7,5, uma vez.
- **Limites.** O mapa foi feito pelo Claude. Acurácia é piso de qualidade, e as divergências (R4) precisam de olho humano antes de concluir que "o Gemini errou". Se algum tema passar de ~400 clusters, T2/T3 ficam caros; a saída é busca vetorial para reduzir o catálogo por chamada (fase 2).
- **ROI no agente.** Com ~40 ideias/mês, o ganho em produção é pequeno. O valor está em consistência e em um possível reprocesso do backfill, não em economia mensal.

### AUX-O · Onboarding · sem script (protocolo)

- **Por que sem script.** A transcrição vem do MeetRox por `curl` com chave que só existe no ambiente de nuvem; não está no BigQuery. Preciso que você exporte uma amostra.
- **A regra que manda.** I5: o resumo nunca vira sinal; compressão ou amostragem derruba o dia para `⚠️`; a `prova_de_leitura` é um trecho literal dos últimos ~20% da transcrição redigida. Então o auxiliar **não pode substituir** a leitura. Só cabe como **leitor paralelo (sombra)**: o Gemini lê a transcrição íntegra e redigida, extrai as dificuldades, e a comparação é com as do Claude. Isso testa se o Gemini seria um segundo leitor confiável, não se pode poupar o Claude.
- **Entrada pedida.** 30 reuniões de um dia útil, já redigidas pela rotina determinística do agente, em `contaazul-datalake-dev.dataform.tmp_aux_onb_transcricoes (call_id STRING, data DATE, transcricao_redigida STRING)`. Mais as dificuldades que o agente gravou para esse dia (DB de Sinais do Onboarding, ponto de série do dia).
- **Saída do Gemini.** `sinais[]` com `assunto`, `tema` (9), `estagio`, `friccao` (`parou`/`pendente`/`duvida_forte`), `evidencia` (≤4 verbatims de ≤15 palavras), seguindo o schema do MD (`onb:332-356`).
- **Métricas.** (a) Recall das dificuldades do Claude (mesmo assunto, juízo humano) e precisão do que o Gemini acha a mais; (b) PII no que o Gemini devolve (deve ser zero); (c) `prova_de_leitura` reproduzível pelo Gemini; (d) tokens: ~25 mil de entrada por reunião ≈ **US$ 0,006**/reunião, ~US$ 0,25/dia em 40 reuniões.
- **Decisão que o teste não toma.** Se o dono aceita um segundo leitor barato como gate extra. A decisão de 2026-09-10 (ler tudo, rejeitar embeddings e compactação) continua valendo.

### AUX-X · Cross · sem script (opcional)

- **Por que baixa prioridade.** O Cross não lê texto cru; a `Descrição` já é uma frase; a `Leitura` deve entrar no corpo da OP com a "inteligência" e não diluída (`cross:440,471`). O cold start (~1,1M tokens, ~US$ 7) é raro; o regime estável é pequeno.
- **Se quiser testar.** Pré-agrupar as `Descrição` de ~630 sinais com o Gemini e comparar, par a par, com a pertença real às OPs (back-links). Exige exportar sinais e OPs do Notion. Compara com `cross:332` (clusterização central 1×).

## 4. Métricas e critérios de aceite

Os limiares são **proposta minha**, ancorados no que medimos antes (o prompt de produção reproduz o gravado em 85 a 88%, com repetições idênticas; JSON sem `output_schema` válido em 99 de 99). Ajuste depois da primeira rodada.

| Gate | Critério | Vale para |
|---|---|---|
| G0 técnico | JSON válido ≥ 99%; zero id fora do catálogo; repetição idêntica ≥ 95% | Todos |
| G1 fidelidade agregada | **Suporte:** Spearman ≥ 0,85, top-10 em comum ≥ 8, erro relativo médio top-30 ≤ 30%. **pNPS:** Spearman N2 ≥ 0,90, desvio ≤ 20% nos N2 com ≥10 menções, "Sem tema" a ±5 p.p. **Portal:** tema ≥ 85%, cluster (oráculo) ≥ 70%, NEW correto ≥ 60% | AUX-S, N, P |
| G2 conjunto rotulado | 50 itens por agente, rotulados por especialista; precisão do Gemini ≥ precisão do agente atual. **Sem isto, nenhuma conclusão de acerto.** | Todos |
| G3 direção do erro | Match errado ≤ 5% dos itens; o resto dos erros deve ser falso NEW | AUX-S, P |
| G4 operacional | Zero PII devolvida; custo do estágio 1 documentado; latência medida (hoje só tenho o 2,125 s de um job, ainda sem confirmar qual era) | Todos |

## 5. Ordem de execução

| Passo | Quem | O quê | Pré-requisito |
|---|---|---|---|
| 1 | Você | Rodar `teste_aux_gemini_suporte_catalogo.sql` (seções 1 a 4, depois R1 a R8 uma por vez) | Acesso ao dev; opcional: `n_reps = 2` |
| 2 | Você | Completar a lista de 16 N2 e rodar `teste_aux_gemini_pnps.sql` | Lista de N2 do schema do agente |
| 3 | Você | Rodar `teste_aux_gemini_portal_ideias.sql` | — |
| 4 | Eu | Ler os resultados, comparar com os limiares, apontar divergências para rótulo | Os resultados colados aqui |
| 5 | Time de Suporte, de pNPS e de Portal | Rotular os 40 a 50 itens de cada amostra (R8, R7, R4) | Passo 4 |
| 6 | Você + dono do Onboarding | Decidir se vale o teste-sombra (AUX-O) e exportar 30 transcrições | I5 |
| 7 | Eu | Fase 2 (seção 6) só nos agentes que passarem G0 a G3 | Decisão sua |

Custo total das fases 1 e 2 de Suporte, pNPS e Portal: **abaixo de US$ 10** de Gemini, mais o custo de tokens do Claude na fase 2.

## 6. Fase 2: o especialista com a entrada reduzida

Só depois de passar G0 a G3. O objetivo é medir o que a fase 1 não mede: **tokens reais do Claude** e **concordância de cluster**.

- **Dois braços, mesma amostra.** Controle (como é hoje) e tratamento (com a saída do auxiliar como entrada ou como pré-agrupamento). Rodar o passo de classificação e reconciliação do agente com subagentes puros (somente leitura e JSON, como o MD exige), registrando o `usage` de cada chamada.
- **Métricas.** Tokens de entrada e saída por braço; concordância par a par dos agrupamentos entre os braços (e contra o rótulo humano, quando houver); top-N de sinais; tempo.
- **Suporte, dois formatos.** (A) Gemini entrega campos por item e o Claude agrupa; (B) Gemini casa com o catálogo e o Claude trata só o "sem match" e a consolidação. A comparação diz qual redução de tokens sustenta a troca.
- **Execução.** Eu rodo na sessão (com a amostra do dia de 19/10 já tratada) ou você roda o agente de dev com `Run now`. Observação: `routines/dev/` hoje é cópia anterior à inversão dev/prod e o runbook de migração manda tratar a V2.5 como apagada; use o prompt de `routines/prod/` como base.

## 7. Riscos e decisões que são do dono do produto

1. **Onde o auxiliar vive em produção.** Na camada de dados (Dataform), como o `ai_issue_summary` e a coluna B da reformulação A + B. Dentro do agente, não cabe: um agente tem um modelo só.
2. **Qualidade do pré-LLM existente.** O `ai_issue_summary` tem corrupção crônica de substrings desde ≥20/08 (`cancelar`→`ncelar`) e ~23 a 28% de conversas sem resumo. Um auxiliar com prompt próprio e instrução de inferir o texto pode melhorar isso. Vale medir nos itens de R8.
3. **Regras a rever para outros agentes.** "Determinístico e reprodutível" (pNPS) e I5 (Onboarding) são decisões de design, não limites técnicos.
4. **Documentação defasada.** O `CLAUDE.md` do repositório ainda descreve a V2 com taxa 25% e ~400 a 500/dia; a Central é legado e `unverified`. Qualquer decisão de produção deve conferir o prompt em `routines/prod/`.
5. **O modelo.** O teste usa `gemini-3.1-flash-lite` em `us.vertex_connection`, como os testes anteriores. O endpoint de produção da `dim_voc` (global) pode se comportar diferente; os 12 a 15% de divergência que medi antes ainda não têm causa confirmada.

## 8. Arquivos

| Arquivo | O que é |
|---|---|
| `teste_aux_gemini_suporte_catalogo.sql` | AUX-S (população validada em prod: 707 conversas) |
| `teste_aux_gemini_pnps.sql` | AUX-N (população validada em prod: 334 comentários) |
| `teste_aux_gemini_portal_ideias.sql` | AUX-P (não executado; depende das tabelas de dev que ele cria) |
| `justificativa-design-agente-suporte-v2.md` | Justificativa de design da V2 |
| `comparativo-ab-vs-sense2-0.md`, `simulacao-dia-2026-10-19-sense2-vs-ab.md` | A + B do Suporte, que este plano estende |

**Não validado:** as consultas de resultado (R1 em diante) e as chamadas `AI.GENERATE` dos três scripts nunca rodaram; só as seleções de população foram executadas como leitura em prod. Se der erro de sintaxe ou de coluna, cole a mensagem e eu corrijo.
