# Justificativa de design: Agente Especialista de Suporte V2 (prod)

29/10/2026. Base: `routines/prod/agente-especialista-suporte-v2.md` do repositório `sense-platform`, páginas Notion ligadas a ele e histórico git do arquivo. Quando algo é **inferência minha**, está marcado como tal.

## 0. Fontes e limites desta leitura

| Fonte | Estado | Observação |
|---|---|---|
| `routines/prod/agente-especialista-suporte-v2.md` (481 linhas) | Lido por inteiro | Clone local em `341512e` (17/10/2026, PR #295). Não fiz `git fetch`, então commits posteriores a 17/10 podem não estar aqui. |
| `CLAUDE.md` e `routines/MIGRACAO-PROD-SENSE-2.0.md` | Lidos (CLAUDE.md até a linha 411 de 582) | O `CLAUDE.md` ainda descreve a V2 com "~400–500/dia, amostra 25%", valores antigos. O prompt prod diz 30%, ~795/dia. |
| [Sense — Central](https://app.notion.com/p/3a34a554a42f8118ae36fe0582381266) | Lido | Página marcada como **legado** na árvore do Notion, `unverified`, última edição de conteúdo em 14/09/2026. É a fonte do que está "no ar hoje", como você pediu. |
| Notion: Arquitetura do report — Suporte (23/07), Manual de seleção de modelo (24/08), Manual de criação de Especialistas (24/08), Categorização VoC por LLM (04/09) | Lidos | Todas `unverified`. |
| Histórico git do arquivo (V2 prod/dev e V2.5 dev) | Lido | Mostra qual incidente gerou cada regra. |

Não existe um documento único de ADR para a V2. O "porquê" está em quatro lugares: o cabeçalho do prompt, as regras com marca de incidente dentro do prompt, as mensagens de commit e as páginas Notion de arquitetura.

## 1. Resumo

A V2 existe por uma razão econômica e uma operacional:

1. **Volume.** O Suporte cresceu 11× em 5 meses (4,3 mil conversas em fevereiro, 49 mil em julho). A v1 classificava o censo (~2.300 conversas/dia) em 15 a 18 shards, uma abordagem O(N) que a Notion de arquitetura estima em ~24 shards e ~1,3M tokens/dia. Mais volume significava mais shards e mais pontos de falha (gate de permissão, estouro de token).
2. **Casca frágil.** A v1 quebrou repetidamente por causa do sharding (subagentes escrevendo `.py` e arquivos, colisão de scratchpad, truncamento por fan-out de JOIN).

A resposta foi trocar **censo por amostra** e **muitos shards por uma sessão única**, mantendo o "cérebro" da v1 (cluster granular, catálogo vitalício, emite sinal e não OP). O que muda é só a entrada e a matemática da contagem.

O resto do prompt é, em sua maior parte, **cicatriz de incidente**: cada regra dura aponta para uma run que falhou (05/08, 04/09, 05/09, 11 a 14/09, 10 e 14 a 17/10).

## 2. O que está no ar hoje (segundo a Central) e onde o prompt diverge

| Item | Central (14/09, legado) | Repositório (17/10) | Leitura |
|---|---|---|---|
| Agentes | 5 standalone, sem orquestrador: Suporte, pNPS, Onboarding, Portal, Cross | Mesmos 5 em `routines/prod/` | Coincidem. Sense 1.0 está paralisado. |
| Cadência Suporte | Diário 04:00 (D-1) | 4h BRT pela UI de Scheduled Task | Coincidem. O changelog 2.1.0 da própria Central ainda diz "roda à noite", o que é anterior ao commit de 14/09 que moveu para 4h. |
| Cadência Onboarding | Diário 9:00 | O runbook de migração (v10) ainda fala "quinzenal"; o `CLAUDE.md` diz diário | Documentação inconsistente. Adoto a Central (diário). |
| Cadência Cross | Mensal, dia 3 | `CLAUDE.md`: Cross às 7h, Report Mensal dia 4 às 11h | Coincidem no mensal; o dia exato não foi conferido. |
| Taxa de amostra | Não citada | Prompt prod: 30%, ~795 selecionadas, ~640 classificadas | `CLAUDE.md` (25%, ~400–500) está defasado. |
| Re-síntese da Leitura | Não citada | Prompt prod: conjunto `RESSINTETIZAR` desde 17/10 | A Central não registra essa mudança (último changelog é 2.1.0, 11/09). |

## 3. Decisões de design e justificativa

Legenda: **Doc** = justificativa escrita no prompt, Notion ou commit. **Inf** = inferência minha.

| # | Decisão | Justificativa | Evidência | Trade-off aceito |
|---|---|---|---|---|
| D1 | **Amostra, não censo** | O censo é O(N) num volume que cresceu 11× em 5 meses. A amostra de 30% é "~3× menor" mas continua proporcional ao volume. (Doc) | Prompt `:5`, `:22` | Cauda rara escapa; contagem vira estimativa; Score é ordinal. Custo constante só com embeddings (V3). |
| D2 | **Selecionar só por metadado em SQL** | "Escolher ≠ entender": o SQL escolhe, o LLM só lê as escolhidas. Evita ler conteúdo para decidir. (Doc) | `:18`, `:198`, `:203` | Pré-filtro de ruído é só `ai_issue_summary` vazio, sem heurística por tamanho ou palavra. |
| D3 | **Censo de gravidade + amostra do resto** | N2/N3 e sentimento muito negativo são raros e densos em dor, entram inteiros (×1). O resto é amostrado por hash determinístico. (Doc) | `:19-21`, `:199-201` | Taxa 25/40% já rodados deram o mesmo conjunto de problemas, por isso 30% (decisão do user em 30/07). |
| D4 | **Hash determinístico `MOD(MOD(FARM_FINGERPRINT(...))+D, D)`** | `ABS(FARM_FINGERPRINT)` estoura em `INT64_MIN`. A forma escolhida fica sempre em `[0,9]` e a conversa cai sempre no mesmo balde. (Doc, review CodeRabbit L168) | `:201` | Nenhum. |
| D5 | **Grão = cluster granular vitalício, entendido pelo LLM** | A classificação pronta do Intercom (`subjects`/`subcategory`) é vazia em 30–49% e grossa, o que gera "sinal raso, OP rasa". O tipo do problema emerge do que o LLM lê. (Doc) | `:17`; Notion Arquitetura §2 e §10 | Depende de o LLM nomear de modo estável. |
| D6 | **Proibido regex e palavra-chave para agrupar** | Regex "casa padrão em vez de entender": junta problemas que dividem substantivo e separa o mesmo problema com outras palavras. A estreia de 29/07 usou essa muleta e foi apontada. (Doc) | `:215` | Exige raciocínio semântico, que é onde está o custo (D14). |
| D7 | **Dois grãos: fricção/bug vs descoberta** | How-to recorrente é "feature difícil de achar", sinal que a V2 quer captar. Mas cada "como faço X" fraseado diferente fica abaixo do piso e some. Medido em 29/07: ~28% da amostra era how-to pulverizado. Daí `Descoberta: <feature>`. (Doc) | `:221-226`; commit `856d9f7` | Grão de descoberta é a feature específica, nunca balde genérico. |
| D8 | **Clusterizar o `ai_issue_summary`; ler `message_body` só na Leitura** | O resumo Gemini já pronto é barato, sem join nem PII, e granular. O `message_body` (caro) só entra nos clusters que viram sinal. (Doc) | `:23`, `:135`, `:373` | Depende de um pré-LLM externo (ver seção 5). |
| D9 | **Sessão única, sem Workflow tool, no máximo 2 a 3 shards Task** | ~640 resumos de 1 linha cabem num contexto. O over-split da v1 era artefato de 15–18 fatias que não se enxergavam. A Workflow tool "pede gate a cada lançamento, trava run desatendida". (Doc) | `:25`, `:38-40`, `:213`; Notion Manual de modelo §2 | Se não couber, shard obrigatório com barreira de set-equality. |
| D10 | **Subagente puro: só leitura MCP, sem Bash/Write** | Em 29/07 subagentes escreveram scripts `.py` e arquivos, causando prompt de permissão, colisão de scratchpad e estouro de token. (Doc) | `:40` | Subagente grande demais significa mais shards menores, nunca disco. |
| D11 | **Contagem escalada por balde; piso em contagem crua** | O cluster mistura baldes. Somar cru infla o número; multiplicar o cluster por 4 também. Cada balde pesa `1/taxa`. O piso de ≥3 usa conversas cruas para a admissão não depender da taxa (senão uma única conversa amostrada a 30% ×3,33 já passaria). (Doc) | `:29-32`, `:204`, `:330` | Score vira estimativa. |
| D12 | **Consolidar (fundir) antes do piso** | Um problema real de 30 chamados partido em dois de 15 cairia abaixo do piso e sumiria. Três camadas anti over-split: fundir antes de contar, passada única, matching no catálogo. (Doc) | `:27`, `:299`, `:330` | Merge é conservador: na dúvida, não funde. |
| D13 | **Barreira de reconciliação fail-closed (partição exata por `cid`, duas vezes)** | A run de 05/08 deixou 472 de 744 classificadas sem destino. Depois, a de 04/09 formou 9 clusters de 768 (81% sem partição). Cobertura passou a ser binária: fecha ou falha alto. (Doc) | `:301-309`, `:332-346`; commits `e7c44a3`, `90aac93` | Run `❌` em vez de `⚠️` silencioso. |
| D14 | **`inference_failed` como estado explícito** | O `ai_issue_summary` tem corrupção crônica desde ≥20/08 (substring "ca" removida: `cancelar`→`ncelar`). O texto é legível por inferência, e despejar o não-inferível em `misc` fingiria cobertura. (Doc) | `:344`; commit `8a96348` | Força retry e, se persistir, falha. |
| D15 | **Modo A (merge de candidatos) sempre ligado; Modo B (arquivar cluster persistido) desabilitado** | O Notion não tem compare-and-set atômico nem coluna `cluster_id` imutável. Arquivar sem ledger destruiria história. (Doc) | `:313-328` | Duplicatas já persistidas só são logadas para curadoria. |
| D16 | **Zero tabela BQ própria; catálogo vitalício e estado vivem no Notion** | O grão granular não existe como coluna pronta; a clusterização é nossa, mas persiste no Notion. Chave canônica = título normalizado do `Sinal`. (Doc) | `:24`, `:326` | Sem `sinal→cid` persistido: sinal dormente sem Leitura não é re-sintetizável (`:371`). |
| D17 | **Emite sinal, não cria OP; Cross mensal consome** | Separação de responsabilidades: especialista lê uma fonte; o Cross cruza fontes e prioriza. (Doc) | `:11`; Central, "Como funciona" | `OP Sense` nasce vazio e nunca é sobrescrito. |
| D18 | **DBs isoladas da v1, allowlist fechada, blocklist dev↔prod, bootstrap fail-closed** | Um ID errado é leak dev↔prod. A v1 fica em dev como fallback intocável. (Doc) | `:7`, `:54-70`, `:184-188`; Runbook de migração | Qualquer não-200 de recurso pinado aborta, sem discovery por título. |
| D19 | **Guard de fan-out no JOIN do Zendesk, `CAST` na chave** | `dim_zendesk_tickets_detailed` tem grão de ticket, e N tickets por conversa multiplicam linhas. Bug real de 07/08 08:00 truncou 2 de 3 shards. A chave é INTEGER numa tabela e STRING na outra. (Doc) | `:121-134` | Dedup `QUALIFY ROW_NUMBER()` com ordenação determinística. |
| D20 | **Deflection global sobre o universo inteiro, por cluster ponderada** | O universo (inclui bot-only e pré-filtradas) é o denominador: é agregado barato de metadado, sem LLM. Por cluster usa peso `1/taxa`. (Doc) | `:196`, `:287-289` | Bot-only que não caiu na amostra não aparece em cluster. |
| D21 | **Quem fala medido por mês, ponderado, aditivo** | O percentual do dia num cluster pequeno saía "Baixo 0%" com frequência (~28% sem identificação). A medição que o Cross lê é mensal e **não pode derrubar a run diária**. (Doc) | `:165-170`, `:381-390`; commits `9abafd9`, `b6d322d` | Começa em 2026-11 (outubro seria mês parcial). |
| D22 | **Leitura em 4 partes e emoção só licenciada por aspa ou campo `sentimento`** | Traz a voz do cliente sem virar bloco grande. Reincidência não vira "raiva"; tempo longo não vira "dor". (Doc) | `:352-357`; commits `d4d348e`, `429c9d2` | Sem aspa nem sentimento, descreve neutro. |
| D23 | **Re-síntese por movimento material (`RESSINTETIZAR`)** | A regra anterior reescrevia 100% dos ativos todo dia, dimensionada para ~20–50. O catálogo passou de 250 e um dia útil tem ~120–170 ativos. As runs de 10/10 e 14 a 17/10 cortaram a síntese por conta própria e fecharam `⚠️`. Texto muda só com gatilho; número é atualizado todo dia. (Doc) | `:358-369`; commits `8cbec4c`, `bdf28d8`, `3a619be`, `d39b1f8` | Texto antigo com marca de data significa "sem mudança relevante". |
| D24 | **Janela D-1 em BRT, fim de semana e feriado tratados como sazonais** | Bug 11 a 14/09: data tomada em UTC perto da meia-noite processava o dia corrente parcial. Sáb/dom ≈ 5% do volume, então queda de fim de semana não é queda de produto. (Doc) | `:137-143`; commit `6c293e3`, `d15ecda` | Se D-1 não fechou, aborta sem escrever, em vez de processar parcial. |
| D25 | **Score ordinal, sem cap** | Serve para ranquear, não é gauge. Capar achataria dois tops distintos. Teto teórico ~410, tops práticos 100 a 180. (Doc) | `:348-349` | Ratios da fatia amostrada têm ruído. |
| D26 | **Roteamento de modelo por agente, não por etapa** | Um agente é uma sessão e um modelo no main loop. A política por sub-agente (shards Sonnet/Haiku) foi tentada em 28/07 e revertida: gerou enxurrada de prompt de permissão e não cortou custo, porque o custo é volume de transcrição e não preço por token. (Doc) | Notion Manual de modelo §2–§3 (PR #143) | Reavaliar só junto de redesenho de compute. |

## 4. Como o design evoluiu (derivado do git e do prompt)

| Data | Evento | Regra que nasceu |
|---|---|---|
| 28/07 | Suporte v1 troca sessão única por workflow de shards; política de tier por sub-agente tentada e revertida (PR #143) | Modelo por agente |
| 29/07 | Estreia da V2 usou regex para pré-agrupar (536 selecionadas); subagentes escreveram arquivos | D6, D10 |
| 30/07 | V2 criada (`d3f5ece`, PR #159); taxa 25%→40%→30%; piso por contagem crua; lente de descoberta | D1–D3, D7, D11 |
| 05/08 | Run puntou 472 de 744 por orçamento de sessão | D13 (barreira de reconciliação) |
| 06/08 | A/B do Haiku lendo tudo, origem da V2.5 (PR #182, #184, #185) | V2.5 (experimento, "apagada" segundo o runbook de migração) |
| 07/08 | Fan-out de JOIN estourou 2 de 3 shards | D19 |
| 12/08 | Leitura em 4 partes | D22 |
| 13 a 14/08 | Migração dev→prod (G0.5, HARD GATE fail-closed); 1ª run prod gastou ~690k tokens (US$ 4,55) | D18; recalibração da estimativa de tokens |
| 26/08 | Série bounded (diária + mensal + anual); Cross passa a ler o rollup mensal (PR #236, #238) | `Menções (série)` em 3 zonas |
| 03 a 05/09 | Síntese 100% imperativa; reconciliação imperativa; run de 05/09 pendurou num `cp` de `tool-results` (PR #250, #252, #255) | D14; proibição de copiar de `.claude/` |
| 09 a 14/09 | Regra de fim de semana; cron ligado; bug de fuso (data em UTC); agendamento 4h BRT (PR #259, #271) | D24 |
| 14 a 15/10 | Quem fala mensal, aditivo | D21 |
| 17/10 | `RESSINTETIZAR` (PR #295) | D23 |

## 5. Premissas do design e onde estão sob tensão

1. **"O gargalo é o raciocínio semântico, não o payload."** Está escrito no prompt (`:438`): na 1ª run prod, as duas chamadas de Agent (classificação ~353k e reconciliação ~236k) somaram ~589k dos ~690k tokens, cerca de 10× a estimativa original (que dimensionava pelo input). Os logs que li antes mostram média de ~358k tokens e ~US$ 2,4 por run (24 runs, US$ 56,7). Esta é a premissa mais relevante para um LLM auxiliar: o que custa é a parte que o LLM barato poderia assumir.
2. **"Já existe um pré-LLM."** O `ai_issue_summary` (Gemini, gerado fora do agente) é o insumo da clusterização. O próprio agente não controla nem seu prompt nem sua qualidade. Dois sintomas estão documentados: corrupção crônica de substrings (`:344`) e ~23% de conversas sem resumo (`:203`; medi 28% em 19/10).
3. **"Amostra de 30% basta."** O critério de aceite foi comparar 25% e 40% com o censo da v1: deram o mesmo conjunto de problemas (`:201`). Não encontrei um conjunto rotulado por humanos que valide a classificação em si.
4. **"A cauda rara pode escapar."** Trade aceito com a promessa de um agente dedicado de tendência rara (`:22`, `:464`). Não encontrei esse agente em `routines/prod/` nem na Central.
5. **"Uma run por dia basta como exclusão."** O prompt admite que cadência não é lock (`:400`): `Run now` durante a janela pode duplicar sinais. A exclusão real (lease/idempotency-key) é follow-up.
6. **"O catálogo cabe em contexto."** Passou de 250 sinais, e o conjunto ativo diário é de 120 a 170 (`:358`). A cada crescimento, o passo de matching tem mais para ler.

## 6. Ponte para o teste de LLM auxiliar

O design diz, com todas as letras, onde um LLM barato cabe e onde não cabe:

| Pode entrar | Não pode entrar |
|---|---|
| Antes do Passo 3, produzindo campos por item (como o `ai_issue_summary` já faz). | Seleção por conteúdo (D2): o SQL escolhe por metadado. |
| Redação de PII antes de qualquer LLM, hoje obrigatória (`:211`, `:351`). | Regex ou palavra-chave para decidir cluster (D6). |
| Matching contra catálogo (precedente: V2.5 com Haiku, "erro seguro"). | Substituir a `Leitura` por resumo agregado: "proibido substituir a síntese do `message_body` pelo `ai_issue_summary`" (`:373`). |
| | Tabela BQ do nosso lado como estado (D16). Em simulação de dev vale, em produção não. |
| | Modelo por etapa dentro do agente sem sub-agente (Manual de modelo §7). Um pré-LLM **fora** do agente (na camada de dados) contorna isso: o agente continua com um modelo só. |

O ponto de entrada natural para um Gemini 3.1 flash-lite é, portanto, **antes** do agente (camada de dados), no mesmo lugar do `ai_issue_summary`, e não dentro da sessão do Claude.

## 7. Lacunas

- Não li `CLAUDE.md` das linhas 412 a 582 nem as seções "Estimativa de tokens" completas dele.
- Não conferi o dia exato do Cross na Central contra o agendamento real.
- Não consegui confirmar se a V2.5 foi de fato removida do repositório. O arquivo `routines/dev/agente-especialista-suporte-v2.5.md` existe, e o runbook de migração diz "V2.5 apagada — ignorar".
- Não validei o efeito de cada regra em runs. Os números de incidente vêm do próprio prompt, dos commits e dos logs que li antes.
