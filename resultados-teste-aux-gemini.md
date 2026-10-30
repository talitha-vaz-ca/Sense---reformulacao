# Resultados dos testes AUX (Gemini 3.1 flash-lite antes dos agentes)

29/10/2026. Fonte: os CSVs das pastas `teste_aux_gemini_*_output/` que você rodou no dev. Plano e critérios em `plano-testes-llm-auxiliar-gemini-outros-agentes.md`. Os limiares dos gates são propostas minhas, não decisões do time.

> **Atualização, rodada 2 (29/10, tarde; linha de base na seção 10):** os "JSON inválidos" do Suporte eram falha do meu parse (resposta com vários objetos), já corrigida, e a validade foi a 100%. O ranking do Suporte continua em Spearman ~0,60. O Portal v2 corrigiu o erro do script e **não mudou a conclusão**. Detalhes na seção 9.

## Estado atual (30/10/2026)

As seções 1 a 3, 6 e 9.4 trazem números da rodada 1 (por exemplo, JSON do Suporte em 93,2% e Spearman 0,58) e ficam como registro. O que vale hoje é a tabela abaixo, que usa as rodadas 2 e a cobertura de 100% (seções 9 e 11). A conclusão da seção 10 sobre limiares "irreais" foi retratada na seção 11.

| Agente | Estado | Números atuais | Pendente |
|---|---|---|---|
| **pNPS** | Melhor candidato | JSON 99,7%; Spearman 0,89 e Pearson 0,94 contra o agente; 6 de 9 N2 fora de ±20%; ~US$ 0,11 por rodada | Rótulo humano (R7); ajuste do prompt (Facilidade, Elogio a recurso, Pós-venda); `n_reps = 2` |
| **Suporte** | Não substitui o casamento ainda | JSON 100% (parse corrigido); Spearman 0,60 contra a V2, com teto de amostragem de 0,86 (Gemini 30% contra Gemini 100%); 96% das conversas casadas com um catálogo de 53% dos sinais; ~US$ 0,00085 por chamada | R8 rotulado; V2 em 100% não medida; `n_reps = 2` |
| **Portal** | Inconclusivo | JSON 100%; cluster certo 35% (oráculo); backfill grosso, com 930 itens de tema inconsistente | Adjudicar ~50 casos; revisar os clusters com 20 ou mais ideias |
| **Onboarding, Cross** | Sem teste | n/a | AUX-O (30 transcrições exportadas e decisão sobre a regra I5) e AUX-X |

Dos próximos passos da seção 7, os de número 1 a 3 foram executados em 29/10 (seções 9 a 11); os de número 4 a 6 seguem abertos.

## 1. Resumo (rodada 1)

| Agente | Resultado | Leitura |
|---|---|---|
| **pNPS** (AUX-N) | Quase passa | JSON válido em 99,7%; contagens por N2 batem com as do agente (Spearman 0,89, Pearson 0,94). Falha só no desvio por N2 (6 de 9 acima de 20%), e as diferenças vêm de fronteiras de definição. **Melhor candidato.** |
| **Suporte** (AUX-S) | Reprova no estado atual | JSON válido em 93,2% (P2) e 84,4% (P1); ranking do dia com Spearman 0,58 contra a V2; erros de match na amostra. Mas a massa por família de sinais se preserva. |
| **Portal** (AUX-P) | **Inconclusivo** | Achei um erro no meu script e uma inconsistência nos dados de prod (seção 4). Os números de cluster (32%) não valem. O v2 do script corrige. |

Nenhum resultado aqui prova acerto: a verdade de cada teste é a saída dos próprios agentes, e o conjunto rotulado por especialistas (G2) ainda não existe.

## 2. Gates

| Gate | Critério | AUX-S (P2) | AUX-N | AUX-P (v1) |
|---|---|---|---|---|
| G0 JSON válido | ≥ 99% | **Não**: 659/707 = 93,2% (P1: 597/707 = 84,4%) | **Sim**: 333/334 = 99,7%; 0 N2 fora da lista | Sim: T1 387/387; T2 386/387 |
| G0 repetição | ≥ 95% idêntica | Não medido (`n_reps = 1`) | Não medido | Não medido |
| G1 agregado | ver abaixo | **Não** | Parcial | Não confiável |
| G3 erro de match ≤ 5% | | **Provável não** (seção 3) | n/a | Não confiável |
| G2 rótulo humano | ≥ agente atual | Pendente | Pendente | Pendente |

## 3. AUX-S · Suporte V2, dia 19/10

**Números** (população de 707 conversas, a mesma seleção da V2):

| Medida | Valor | Critério |
|---|---|---|
| Spearman do ranking de sinais (100 sinais com verdade) | **0,58** | ≥ 0,85 |
| Pearson | 0,67 | |
| Top-10 em comum | **7** | ≥ 8 |
| Top-20 em comum | 11 | |
| Erro relativo médio no top-30 | **40,8%** | ≤ 30% |
| Soma de menções, 100 sinais | V2 1.597, Gemini 1.542 | |
| Conversas casadas com o catálogo | amostra 95,9%, censo N2/N3 98,1%, censo negativo 100% | |
| Natureza igual entre P1 e P2 (mesma conversa) | 417/594 = **70,2%** | |
| Custo P2 | ~3.122 tokens por chamada, **US$ 0,60/dia** | confere com a estimativa |

**O que aparece nos dados:**

1. **O Gemini redistribui entre sinais vizinhos, mas conserva a massa da família.** Na família "renovação de plano", os cinco sinais visíveis no top-30 somam 236,7 na V2 e 218,4 no Gemini (−8%). Individualmente divergem muito: "Negociação de valor/desconto" 56,3 (V2) contra 108,0 (Gemini); "Aumento/reajuste" 96 contra 42,7; "Renovação sem autorização" 17,7 contra 4,3. O catálogo da V2 tem sinais quase sobrepostos, e o ranking por sinal é sensível a essa fronteira. (Conta feita só com as linhas do `_8.csv`; a família foi escolhida por mim pelo nome.)
2. **Quase tudo casa.** 96% de casamento com um catálogo que tem só 146 dos 273 sinais, apesar de a regra dizer "deixe vazio se claramente nenhum serve", sugere uma tendência a forçar match. Na amostra de rótulo (R8), das 20 casadas: 1 claramente errada (nota em lote casada com "Shopee"), 5 frouxas ou genéricas ("FGTS sem linha legível" em "Dúvida genérica sobre uso do sistema"; "recusa de nota fiscal de compra" em "baixar XMLs"). **Minha leitura, não de especialista:** ~14 de 20 sólidas, ~1 errada, ~5 discutíveis.
3. **As 16 "sem match" da amostra parecem cauda real** (inutilizar notas em lote, notificação de venda, agenda ou Kanban, queda de faturamento). Boa direção do erro.
4. **O R3 usou só linhas com JSON válido** (659 de 707), então 6,8% das conversas ficaram fora da contagem. Parte da diferença de soma e do ranking pode vir daí.
5. **Os "inválidos" provavelmente não são falhas totais.** O R2 soma exatamente 707 (541+16+7, 104+1+1, 37), o que significa que o campo `ruido` veio preenchido em todas as linhas, inclusive nas que o R1 marcou como inválidas. Isso sugere rejeição estrita do `PARSE_JSON` (caractere solto, aspas ou quebra de linha no valor), não ausência de resposta. **Hipótese não confirmada**: o texto bruto não foi guardado. No teste anterior (prompt B, 99 chamadas) deu 99 válidas, então há algo específico destes prompts ou dos resumos com várias perguntas.

**Correção já feita no script** (`teste_aux_gemini_suporte_catalogo.sql`): guarda o texto bruto (`bruto`), conta objetos JSON por resposta (`n_objetos`), lê só o primeiro objeto (regex não gulosa) e ganhou R9/R9b para diagnosticar os inválidos.

**Falta uma linha de base.** Não sei quanto o próprio ranking da V2 varia de um dia para outro por ruído de classificação. Sem isso, não dá para dizer se 0,58 é pior do que "ruído normal do Claude". Sugestão: calcular o Spearman da V2 de 19/10 contra a V2 de 16/10 e 20/10 sobre os mesmos 100 sinais (dados já estão na série do Notion).

## 4. AUX-P · Portal de Ideias

**Resultado do v1:** tema 77,3% (T1); cluster 32,0% (oráculo) e 26,2% (predito); falso NEW 134 de 344; NEW correto 28 de 43 (65,1%). Custo US$ 0,37.

**Esses números não valem.** Dois problemas:

- **Erro meu no script.** Montei o catálogo e os ids curtos pelo tema do **cluster** (`cluster_meta.tema`), mas escolhi o catálogo de cada ideia pelo tema do **item** (`cluster_map.tema`). Quando os dois diferem, o cluster certo não estava na lista que o Gemini recebeu, e o id esperado apontava para outro cluster. Por isso a tabela de discordâncias (R4) mostrava, em alguns casos, um cluster do backfill sem relação com a ideia (ex.: "Retenção do ISS" ligada a "baixar DANFE"), e uma linha ficou em branco.
- **Inconsistência nos dados de prod.** `cluster_map.tema` e `cluster_meta.tema` discordam em **930 dos 10.160 itens (9,2%)**, em 244 dos 1.764 clusters. Exemplo: o cluster "Permitir retenção de imposto em NFS-e para cliente sem inscrição municipal" tem tema Fiscal no mapa e "Cobrança & Boletos" no meta. **Vale mostrar ao dono do agente Portal.**

**Outros fatos dos dados (verificados em prod):** 946 dos 1.764 clusters (54%) têm 1 ideia só; 123 clusters têm 20 ou mais ideias e juntam 4.394 itens (43%); o maior tem 160. Isso torna o "cluster certo" um alvo grosseiro nos clusters grandes (no v1, acerto de 28,5% nos clusters de 20+ contra 55,6% nos de 2 a 4 ideias).

**Dos 30 erros do R4**, em vários o cluster escolhido pelo Gemini parece tão bom quanto o do backfill, mas por causa do erro de lookup não dá para julgar. Não tiro conclusão.

**O que fiz:** `teste_aux_gemini_portal_ideias_v2.sql` (novo arquivo) corrige o catálogo e a comparação (por `cluster_id`), adiciona a variante `completo` (catálogo global de ~1,1 mil clusters, sem roteamento por tema, ~US$ 2) e todas as acurácias também no subconjunto consistente.

**Por tema (T1, v1):** Fiscal 96%, Conciliação 100%, Relatórios 90%, Cadastros 80%; Estoque e Plataforma & UX 53%. Esses valores também estão afetados pela inconsistência.

## 5. AUX-N · pNPS, setembro/2026

| Medida | Valor | Critério |
|---|---|---|
| JSON válido | 333/334 | ≥ 99% ✔ |
| N2 fora da lista | 0 | ✔ |
| Soma de menções | agente 408, Gemini 407 | |
| Spearman N2 / Pearson | **0,893** / 0,936 | ≥ 0,90 (falta 0,007) |
| Top-5 em comum | 4 de 5 | |
| N2 com ≥ 10 menções fora de ±20% | **6 de 9** | |
| "Sem tema" em pontos percentuais | 7,6% (agente) contra 4,7% (Gemini) = −2,9 p.p. | ±5 ✔ |
| Custo | ~US$ 0,11 por rodada | |

**Onde diverge (N2, agente → Gemini):** Facilidade / praticidade 92 → 123 (+34%); Bugs & instabilidade 82 → 57 (−30%); Sem tema 31 → 19 (−39%); Onboarding 15 → 9; Elogio a recurso/IA 12 → 6; **Pós-venda & promessas 1 → 9** (e, no N1, Relacionamento 1 → 11). Recursos faltando 75 → 79 e Suporte lento 36 → 42 batem.

**Leitura:** as diferenças são de fronteira de definição, não de ruído. O Gemini usa "Facilidade" como balde de elogio genérico e "Pós-venda & promessas" como balde para qualquer cobrança de atendimento; o agente separa mais. É corrigível no prompt.

**Cenário em texto livre (R5):** mais de 60 variações distintas (o R5 foi limitado a 60 linhas) para 136 menções em "Bugs" e "Recursos faltando" (ex.: 6 formas de "conciliação bancária falha"). Ele **não** substitui o N3 do agente; o agrupamento e o nome continuam sendo trabalho do Claude, como no desenho proposto. Também ficou menos específico que o agente em "emissão de NF/boleto" (~6 comentários contra 21 menções nos N3 do agente).

**Amostra de 50 (R7), minha leitura:** os rótulos são plausíveis na grande maioria. Discutíveis: "ruim" → Sem tema com valência Crítica; "Excelente controle comercial e financeiro" → Facilidade (poderia ser Elogio a recurso); "maior clareza nos planos comerciais" → Usabilidade (poderia ser Preço). Precisa de rótulo do dono do pNPS.

**Limite:** a "verdade" é a contagem por REGEXP + auditoria do agente, que também não é gabarito.

## 6. O que muda no desenho da proposta (Miro)

| Agente | Antes dos testes | Depois |
|---|---|---|
| pNPS | Gemini rotula N1/N2; Claude abre N3 | **Mantém**, com ajuste de prompt e rodada de estabilidade |
| Suporte | Gemini casa com o catálogo; Claude só os sem match | **Não substitui o casamento ainda.** Reavaliar depois da correção do parse e da linha de base de ruído. Alternativa a testar: Gemini propõe o id e o Claude só valida os de baixa confiança |
| Portal | Gemini sugere tema e cluster | **Sem veredito.** Rodar o v2 |
| Onboarding, Cross | Sem teste | Sem mudança |

## 7. Próximos passos

| # | Quem | O quê | Custo |
|---|---|---|---|
| 1 | Você | Reexecutar as seções 3 e 4 do `teste_aux_gemini_suporte_catalogo.sql` (agora guardam o bruto) e rodar R1, R3, R9 e R9b | ~US$ 0,7 |
| 2 | Você | Rodar `teste_aux_gemini_portal_ideias_v2.sql` | ~US$ 2,5 |
| 3 | Você ou eu | Linha de base do Suporte: Spearman da V2 entre dias | Só leitura |
| 4 | Dono do pNPS | Rotular as 50 linhas do R7 | |
| 5 | Dono do Portal | Olhar as 930 ideias com tema do item ≠ tema do cluster | |
| 6 | Eu | Variante do prompt do pNPS (definições de Facilidade, Elogio a recurso e Pós-venda) e `n_reps = 2` | ~US$ 0,3 |

## 8. Limites

- Nenhuma das consultas R1 em diante foi executada por mim; os números acima são os dos CSVs que você gerou.
- Os rótulos "sólida", "frouxa" e "errada" nas amostras R7 e R8 são minha leitura, sem validação por especialista.
- `n_reps = 1` em todos os testes: não há medida de autoconsistência.
- Não consegui confirmar a causa dos JSON inválidos do Suporte.

## 9. Rodada 2 (29/10, executada por mim no BigQuery do navegador)

Reexecutei as seções 3 e 4 do script de Suporte (que agora guardam o texto bruto) e o script `teste_aux_gemini_portal_ideias_v2.sql` inteiro. Custo estimado: Suporte ~US$ 0,65 e Portal ~US$ 1,91 (variante `completo` US$ 1,54).

### 9.1 Suporte: causa dos JSON inválidos confirmada

| | Rodada 1 | Rodada 2 (primeiro objeto) |
|---|---|---|
| P1, JSON válido | 597/707 | **707/707** |
| P2, JSON válido | 659/707 | **707/707** |
| Respostas com mais de 1 objeto JSON | não medido | P1: **110** · P2: **48** |

Os números de respostas com vários objetos são **idênticos** às quantidades de inválidos da rodada 1 (110 e 48). A causa: quando o resumo tem várias perguntas, o Gemini devolve um **array** com um objeto por pergunta (ex.: `[{S032}, {S075}, {S075}]`), e minha regex gulosa juntava tudo num JSON inválido. G0 passa.

**Ranking contra a V2 (R3), com as 707 linhas:**

| Medida | Rodada 1 (659 válidas) | Rodada 2 (707) | Rodada 2, peso dividido entre os objetos | Critério |
|---|---|---|---|---|
| Spearman | 0,582 | **0,604** | 0,594 | ≥ 0,85 |
| Pearson | 0,668 | 0,661 | 0,662 | |
| Top-10 em comum | 7 | 7 | 7 | ≥ 8 |
| Top-20 em comum | 11 | 10 | 11 | |
| Erro relativo médio, top-30 | 40,8% | 43,7% | 42,8% | ≤ 30% |
| Soma de menções (100 sinais) | 1.597 contra 1.542 | 1.597 contra 1.641 | 1.597 contra 1.639 | |

Os inválidos **não explicavam** a divergência de ranking. G1 do Suporte continua reprovado. Em 48 conversas (6,8%) há mais de um tema, e o Gemini os separa; a V2 conta uma conversa em um cluster só.

### 9.2 Portal v2

Todas as 1.161 chamadas (387 ideias × 3 modos) voltaram válidas. 35 das 387 ideias (9%) têm tema do item diferente do tema do cluster.

| Medida | Oráculo | Predito (tema do T1) | Completo (catálogo global) |
|---|---|---|---|
| Ideias em cluster de 2 ou mais, tema consistente | 309 | 309 | 309 |
| **Cluster certo** | **35,3%** (109) | 28,5% (88) | 33,3% (103) |
| Falso NEW | 116 (37,5%) | 132 | 49 (15,9%) |
| Cluster errado | 84 (27,2%) | 89 | 157 (50,8%) |
| NEW correto (ideias em cluster unitário, 43) | 25 (58,1%) | 24 | 12 (27,9%) |
| Custo | US$ 0,18 | US$ 0,19 | US$ 1,54 |

- **Tema (T1):** 79,1% contra o tema do item e 72,4% contra o tema do cluster.
- **Por tamanho do cluster do backfill (oráculo):** 20 ou mais ideias 32,0% (147); 5 a 19: 33,6% (137); 2 a 4: 64,0% (25); unitário: 58,1% (43).
- O catálogo global (sem rotear por tema) troca falso NEW por cluster errado e não melhora o acerto.

**A correção do script não mudou o resultado** (35% contra 32% no v1). O erro do script existia, mas não era a causa.

### 9.3 O que as discordâncias mostram (leitura minha, 50 casos, sem especialista)

- **30 casos de "cluster errado"** (oráculo): o cluster do Gemini é melhor em ~13; o do backfill é melhor em 4 a 7; equivalentes ou nenhum dos dois serve em 10 a 13. Exemplos em que o backfill parece errado: "Integração bancária de PF" ligada a "integração com o Sicoob"; "Lembretes de vencimento" ligada a "controlar pagamentos antecipados a fornecedores"; "Anexo e parcelas" ligada a "pagamento quinzenal"; "CFOP por produto" ligada a "frase padrão nas informações complementares".
- **20 casos de "falso NEW":** em 5 o cluster do backfill é um match claro (ex.: "BOLETO ÚNICO" contra "boletos parcelados em um único arquivo"; "Lembrete de pagamento para clientes"); em ~14 o match é frouxo; em 1 não tem relação.
- **Leitura:** os clusters do backfill são grossos e às vezes sem relação com a ideia (123 clusters com 20 ou mais ideias, 43% dos itens), então "35% de concordância" **subestima** o Gemini. Ao mesmo tempo, ele é mais exigente que o backfill ao dizer "NEW". Os dados **não sustentam** trocar o passo do Claude nem provam equivalência. Só a adjudicação por quem conhece o Portal resolve.
- O achado dos dados de prod continua: `cluster_map.tema` e `cluster_meta.tema` discordam em 930 dos 10.160 itens.

### 9.4 Estado dos gates depois da rodada 2

| Agente | G0 JSON | G1 agregado | G3 erro de match | Veredito |
|---|---|---|---|---|
| pNPS | Passa (99,7%) | Quase (Spearman 0,89; 6 de 9 N2 fora de ±20%) | n/a | **Melhor candidato**; falta rótulo humano e `n_reps = 2` |
| Suporte | **Passa agora (100%)** | Reprova (Spearman 0,60; erro 44%) | Provável não (amostra R8) | Não substitui o casamento; reavaliar como "Gemini propõe, Claude valida" |
| Portal | Passa (100%) | Não aplicável: a verdade é ruidosa | Sem verdade confiável | **Inconclusivo**; precisa de adjudicação humana de ~50 casos e de revisão dos clusters grossos |

### 9.5 Pendências

1. Linha de base do Suporte: Spearman da V2 de 19/10 contra a V2 de 16/10 e 20/10 nos mesmos 100 sinais.
2. Rótulo humano: R8 (Suporte), R7 (pNPS) e as 50 discordâncias do Portal acima.
3. `n_reps = 2` nos três testes (autoconsistência nunca foi medida).
4. Mostrar ao dono do Portal: os 930 itens com tema inconsistente e os clusters com 20 ou mais ideias.

## 10. Linha de base: o quanto a própria V2 se repete entre dias (Notion, 29/10)

**Pergunta:** o Spearman de 0,60 do Gemini contra a V2 é ruim comparado com a estabilidade da própria V2?

**Método.** Li na DB de Sinais V2 (prod) a série `[diário]` dos mesmos 100 sinais do teste (os que tiveram menção em 19/10) para 9 dias úteis (13 a 16/10 e 19 a 23/10). Ponto ausente conta como 0 (premissa: a run existiu nesses dias; não conferi o log de cada um). Comparei pares de dias úteis consecutivos com as mesmas métricas do teste. Spearman calculado como no BigQuery (`CORR` dos `RANK()`, empate pelo menor posto).

| Referência | Comparado | Pearson | Spearman | Top-10 em comum | Top-20 em comum | Erro relativo, top-30 |
|---|---|---|---|---|---|---|
| 19/10 (seg) | 16/10 (sex) | 0,58 | 0,25 | 5 | 10 | 66,6% |
| 19/10 | 20/10 (ter) | 0,56 | 0,46 | 6 | 10 | 65,3% |
| 20/10 | 21/10 | 0,63 | 0,50 | 7 | 12 | 54,1% |
| 21/10 | 22/10 | 0,61 | 0,50 | 5 | 10 | 65,0% |
| 22/10 | 23/10 | 0,64 | 0,56 | 5 | 13 | 54,0% |
| 16/10 | 15/10 | 0,73 | 0,60 | 6 | 9 | 59,6% |
| 15/10 | 14/10 | 0,67 | 0,47 | 5 | 8 | 57,1% |
| 14/10 | 13/10 | 0,69 | 0,46 | 5 | 10 | 61,0% |
| **Média dos 8 pares** | | **0,64** | **0,48** | **5,5** | **10,3** | **60,3%** |
| **Gemini contra a V2, 19/10** | | **0,66** | **0,60** | **7** | **10** | **43,7%** |

**Leitura.**

1. **O Gemini concorda com a V2 do mesmo dia tanto quanto, ou mais do que, a V2 concorda com ela mesma de um dia para o outro.** Nos dois pares justos (os que envolvem 19/10, que é o dia em que os 100 sinais foram escolhidos): Spearman 0,25 e 0,46, top-10 de 5 e 6, erro de 65 a 67%. O Gemini fica em 0,60, 7 e 44%.
2. **(Corrigido na seção 11) Meus limiares eram irreais para esta métrica.** Spearman ≥ 0,85 e erro ≤ 30% não são atingidos nem pela V2 contra ela mesma. Com contagens pequenas (múltiplos de 3,33 numa amostra de 30%), o ranking de 100 sinais é ruidoso. O G1 do Suporte, calibrado por esta linha de base, **passaria**.
3. **Mas a comparação não é equivalente.** A V2 de dois dias usa conversas diferentes (amostra de 30% sorteada de novo) e volume real diferente; o Gemini e a V2 do mesmo dia usam **as mesmas 707 conversas**, então o que difere ali é só o classificador. O baseline mede estabilidade da V2 ao longo do tempo, não o "teto" de concordância entre dois classificadores. O baseline certo seria a V2 classificando as mesmas 707 conversas duas vezes, que não existe.
4. **O ranking não vê o erro de match.** A direção do erro (o Gemini forçando match, 96% de casamento com um catálogo de 53% dos sinais, 1 errada e ~5 frouxas em 20 casadas) continua sendo o ponto fraco do Suporte, e é o G3, não o G1.

**Veredito do Suporte, atualizado (superado pela seção 11, que volta o G1 a "reprovado"):** G0 passa (100%); G1 passa contra a linha de base da V2, mas não contra os limiares originais, que descarto; G3 continua provável reprovado; G2 pendente. Para decidir, falta medir a taxa de match errado com rótulo de especialista (R8) e, se possível, a autoconsistência (`n_reps = 2`).

## 11. Cobertura de 100% da população do dia (19/10) e correção da seção 10

**O teste respeita a amostra de 30% da V2?** Sim. A população de 707 reproduz a seleção da V2: censo N2/N3 (106) + censo "muito negativo" (37) + amostra de 30% por hash do resto (564), com pesos 1 e 3,33. A soma dos pesos (2.023) fica 3,2% acima da população real com resumo (1.961), porque a taxa efetiva da amostra foi 31,0% (564 de 1.818) e não 30%.

**O que rodei:** o mesmo prompt P2, o mesmo catálogo de 146 sinais e a mesma leitura do primeiro objeto, nas **1.254 conversas com resumo que a V2 não amostra**. Total classificado: 1.961. Validade do JSON 100%; 1.187 casadas (94,7%), 25 ruído, 42 sem match; 82 respostas com mais de um objeto. Custo estimado ~US$ 1 (tabelas temporárias no dev, expiram em 7 dias).

**Comparação nos mesmos 100 sinais:**

| Par | Soma ref. / comp. | Pearson | Spearman | Top-10 | Top-20 | Erro top-30 |
|---|---|---|---|---|---|---|
| **A)** V2 (30%) contra **Gemini 100%** (contagem exata) | 1.496 / 1.597 | 0,65 | **0,53** | 7 | 12 | 46% |
| **B)** Gemini 30% escalado contra Gemini 100% (mesmo classificador, só muda a amostragem) | 1.496 / 1.641 | 0,95 | **0,86** | 9 | 17 | 26% |
| **C)** V2 (30%) contra Gemini 30% (mesma amostra; seção 3) | 1.597 / 1.641 | 0,66 | **0,60** | 7 | 10 | 44% |

**Leitura:**

1. **A amostragem de 30% é boa para o topo.** Com o mesmo classificador, 30% escalado reproduz a contagem exata com Spearman 0,86, 9 de 10 no top-10 e 26% de erro. O ruído só de amostragem é pequeno.
2. **A divergência com a V2 vem do classificador, não da amostra.** Passar o lado do Gemini para 100% não aproxima da V2: o Spearman **cai** de 0,60 (C) para 0,53 (A), porque a V2 deixa de compartilhar a mesma amostra com o Gemini. O gap C contra B (0,60 contra 0,86) é a parte atribuível a "Claude e Gemini agrupam diferente".
3. **Correção da seção 10.** Eu disse que os limiares originais (Spearman ≥ 0,85, erro ≤ 30%, top-10 ≥ 8) eram irreais. Estavam certos como teto: são exatamente o que a amostragem sozinha produz com um classificador idêntico (B: 0,86, 26%, 9). A "linha de base" V2 contra V2 entre dias (0,48) mede outra coisa, porque mistura volume real diferente por dia e amostras diferentes, e não deve ser usada como critério de aceite. **O veredito de G1 do Suporte volta a "reprovado" (0,60 contra um teto de 0,86)**; o que o Gemini ainda não consegue é reproduzir o agrupamento do Claude nos sinais vizinhos.
4. **Viés de seleção.** Os 100 sinais foram escolhidos pelos valores da V2 em 19/10, então V2 e Gemini 30% saem inflados contra o exato (1.597 e 1.641 contra 1.496). Parte vem da escala ×3,33 contra a taxa efetiva de 31%, parte de escolher sinais com amostra alta.
5. **O que não medi:** a V2 em 100% (o Claude lendo os 1.961 resumos). Contra o Gemini 100% eu esperaria algo entre 0,53 e 0,65 (a diferença seria só o classificador), mas isso é estimativa minha. O custo seria da ordem de 3 vezes o de uma run da V2.
6. **Custo de ter o Gemini em 100%:** ~US$ 1,7 por dia para o casamento (707 chamadas custaram ~US$ 0,60; 1.961 custam cerca de 2,8 vezes isso). Em troca vêm contagens exatas e a cauda rara visível, sem o ruído da escala.
