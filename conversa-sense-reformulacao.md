# Conversa — Sense 2.x · Proposta de reformulação

- **Projeto:** sense - reformulação
- **Exportado em:** 27/10/2026
- **Deck resultante:** [Sense 2.x · Proposta de reformulação](https://claude.ai/artifact/7tFzcttsJ4UXSh6CULinnS)
- **Base de conhecimento:** pasta “Sense - reformulacao” no Google Drive (documento de contexto da proposta e documento de arquitetura das tabelas VoC no Dataform)

> Os trechos em itálico entre colchetes resumem as ações feitas pelo Claude com ferramentas (leitura de arquivos, criação e publicação dos slides). As mensagens do Claude estão reproduzidas como foram enviadas.

---

## 1. Pedido inicial

**Usuária:**

> com o conhecimento que temos na pasta Sense - reformulacao, formule uma apresentação de proposta de projeto. Dê enfoque aos pontos positivos de processamento, aumento de range de dados [saindo de amostral para populacional] e economia de finops. inicie a apresentação com o comparativo as is e to be da arquitetura, destacando o volume de agentes de ia

*[O Claude localizou a pasta “Sense - reformulacao” no Google Drive e leu os dois documentos dela. Em seguida, criou um deck de slides com o Conta Azul Design System (fonte Ping Pong e paleta da marca) e publicou os sete primeiros slides. O logo do design system não pôde ser copiado, então a capa usa “Conta Azul” em texto.]*

**Claude:**

A apresentação está criada e parcialmente montada: [Sense 2.x · Proposta de reformulação](https://claude.ai/artifact/7tFzcttsJ4UXSh6CULinnS). Ela usa o Conta Azul Design System, com a fonte Ping Pong e a paleta da marca. O conteúdo vem dos dois documentos da pasta Sense - reformulacao no Drive: o contexto da proposta e a arquitetura das tabelas VoC no Dataform.

**Já está no deck (7 slides):**
- **Capa:** "Do amostral ao populacional".
- **Comparativo As-Is × To-Be:** destaca o volume de agentes. Hoje são 5 sessões agênticas em duas esteiras paralelas. Na proposta fica 1 agente recorrente (Cross), mais o Aprofundador sob demanda.
- **"Cada tarefa no executor certo":** mostra para onde vai o trabalho de cada agente (SQL, extração em batch, embeddings, agente). Também registra por que Single Agent e PySpark foram descartados.
- **Os três ganhos:** D-1 fechado, 100% da população e redução de 70% ou mais no custo do Suporte.
- **Três slides de processamento:**
  - Reexecução sem nova chamada ao LLM.
  - D-1 fechado antes das 04h, com a evidência de +10% no Zendesk, +109% na aquisição e NPS de 0 para 41 depois do horário dos agentes.
  - Esteira em camadas nativa do BigQuery.

**Escritos, mas ainda não salvos no deck:**
- Os dois slides de cobertura: o ×3,33 da amostra contra 100%, e os 2.725 leads e 13.328 tickets recuperados.
- O primeiro de FinOps, com o gráfico de custo mensal do Suporte: ≥ US$ 290 no desenho atual escalado, ~US$ 135 hoje por amostra e US$ 30–40 na proposta a 100%.

**Ainda por escrever:** as alavancas de FinOps (dedupe −26%, cache sobre os 91% de template, taxonomia de 30k para 3–6k caracteres), a cascata de modelos T0–T4, as seis fases do plano, as metas de sucesso e as decisões em aberto com próximos passos.

Antes de apresentar, vale saber três coisas:
- **Logo:** não consegui trazer o arquivo do design system, então a capa mostra "Conta Azul" em texto.
- **Valores:** os números em US$ são estimativas de ordem de grandeza e estão marcados assim nos slides e nas notas do apresentador.
- **Orquestrador:** está registrado nas notas que ainda falta confirmar, no Frame 1 do Miro, se a 2.0 roda mesmo sem orquestrador.

Se você responder "continua", eu salvo os três slides prontos e termino os cinco que faltam no mesmo deck.

---

## 2. Continuação

**Usuária:**

> Continuar

*[O Claude publicou os três slides que estavam prontos e escreveu e publicou os cinco restantes, completando 15 slides.]*

**Claude:**

A apresentação está completa, com os 15 slides: [Sense 2.x · Proposta de reformulação](https://claude.ai/artifact/7tFzcttsJ4UXSh6CULinnS).

Nesta rodada entraram oito slides:

- **Cobertura:** "Cada conversa entra na conta" compara o ×3,33 da amostra com 100% das ~1.340 conversas classificáveis por dia. "O que hoje escapa volta para a base" mostra 2.725 leads, 13.328 tickets e o balde genérico de 44%.
- **FinOps, custos:** gráfico do custo mensal do Suporte (≥ US$ 290, ~US$ 135, US$ 30–40) e as reduções de −79% por item, −71% ou mais na Esteira A e −84% no histórico.
- **FinOps, alavancas e cascata:** as seis alavancas e a cascata de modelos T0–T4, com o volume estimado de cada tier.
- **Plano:** as seis fases, cada uma com critério de saída. As fases 2 e 3 aparecem marcadas como shadow.
- **Metas:** tabela "Hoje × Meta" para as sete métricas.
- **Fechamento:** "O que precisamos decidir", com as recomendações e as pendências antes de começar.

Para não pesar os slides, deixei nas notas do apresentador o detalhamento das 11 alavancas, os riscos mapeados e as premissas de preço.

Se quiser, posso deixar a narrativa mais executiva, cortando os slides de camadas e de cascata. Também posso exportar em PowerPoint ou PDF.

---

## 3. Versão executiva

**Usuária:**

> faça com um viés mais executivo, se possível com limite de 10 slides

*[O Claude consolidou o deck em 10 slides: juntou os três slides de processamento em um, os dois de cobertura em um e alavancas com cascata em um; simplificou os termos técnicos; agrupou o plano em três etapas; reduziu as metas a cinco; e transformou o fechamento em pedido e decisões. Como não é possível apagar slides pela publicação, os seis slides cortados foram marcados como ocultos no fim do deck.]*

**Claude:**

A apresentação agora tem 10 slides e um tom mais executivo: [Sense 2.x · Proposta de reformulação](https://claude.ai/artifact/7tFzcttsJ4UXSh6CULinnS). Ela segue um arco simples: como é hoje, o que muda, o que ganhamos e o que precisamos para começar.

1. **Capa**
2. **As-Is × To-Be:** de 5 sessões agênticas para 1 agente recorrente. Os termos técnicos viraram linguagem de negócio, como "classificação em lote, com o modelo mais barato".
3. **Três ganhos:** D-1 fechado, 100% da população e redução de 70% ou mais no custo do Suporte.
4. **Processamento:** "Dado confiável, sem retrabalho". Junta os três slides técnicos em três pares Hoje → Proposta: falhas de IA, dado do dia anterior e operação.
5. **Cobertura:** o ×3,33 da amostra contra 100%, mais os dados recuperados (2.725 leads, 13.328 tickets e o balde genérico de 44% para menos de 5%).
6. **Custo:** o gráfico do Suporte e as reduções de −79%, −71% e −84%.
7. **De onde vem a economia:** as três maiores alavancas e a cascata de modelos em quatro níveis, sem nome de tier.
8. **Plano:** as seis fases agrupadas em três etapas: arrumar a base, construir ao lado e virar a chave.
9. **Metas:** as cinco métricas principais.
10. **Pedido e decisões:** aprovar o início pelas fases 0 e 1, mais três decisões.

O detalhe técnico que saiu dos slides (camadas do BigQuery, horários da publicação, tiers de modelo, riscos e as 11 alavancas) está nas notas do apresentador, para responder perguntas.

Duas coisas para conferir:
- **O pedido do slide 10 é uma sugestão minha.** A proposta original não traz um pedido formal, então vale ajustar a formulação para o fórum onde você vai apresentar.
- **Os 6 slides cortados continuam no fim do deck, ocultos.** Eles não aparecem na apresentação, mas não consigo apagá-los daqui; para limpar, é só excluí-los na página do deck.

---

## 4. Exportação

**Usuária:**

> salve o .md dessa conversa

*[O Claude gerou este arquivo.]*

---

## Anexo — Conteúdo final do deck (versão executiva, 10 slides)

Valores em US$ são estimativas de ordem de grandeza, a partir de medições read-only no BigQuery (`contaazul-ssbi`) de 21/10/2026.

### 1. Capa — Do amostral ao populacional
Proposta de projeto · Sense 2.x. Reformulação da arquitetura de VoC e dos agentes de IA do Sense: mais capacidade de processamento, 100% da população analisada e menos custo. Business Analytics · outubro de 2026.

### 2. Menos agentes, mais cobertura (As-Is × To-Be)
| | As-Is · Sense 2.0 | To-Be · Sense 2.x |
|---|---|---|
| Agentes | **5 sessões agênticas** (Suporte, pNPS, Onboarding, Portal, Cross) | **1 agente recorrente** (Cross mensal) + Aprofundador sob demanda |
| Estrutura | Duas esteiras em paralelo: Esteira A (IA chamada item a item, prompt de ~30 mil caracteres) e Esteira B (agentes) | Uma esteira populacional: entrada padronizada para 8 fontes, classificação em lote com o modelo mais barato, agrupamento automático e contagem exata |
| Pontos de atenção / ganhos | Suporte por amostra (30% fora do censo); estado no Notion; classificação redundante, 14% de concordância | 100% da população; reexecução sem nova chamada ao LLM; Notion apenas como vitrine |

### 3. Três ganhos, uma esteira
- **01 · Processamento — D-1** fechado e imutável antes dos agentes, com reexecução sem nova chamada ao LLM.
- **02 · Cobertura — 100%** da população, com contagem exata, no lugar de censo parcial com 30% de amostra.
- **03 · FinOps — ≥ 70%** a menos no custo mensal do Suporte, já cobrindo 100%: ~US$ 30–40 contra ~US$ 135 hoje.

### 4. Dado confiável, sem retrabalho
| | Hoje | Na proposta |
|---|---|---|
| Falhas de IA | 10,9% dos itens saem “indeterminados” e falha nunca é retentada | Falha vira status e é retentada; reexecutar não paga IA de novo |
| Dado do dia anterior | Incompleto na hora dos agentes: aquisição +109% e NPS de 0 para 41 depois | Dia fechado e publicado antes das 04h, sempre com o mesmo conjunto |
| Operação | Censo dividido em 15–18 shards instáveis e estado guardado no Notion | Uma esteira nativa do BigQuery; Notion só como vitrine |

### 5. Cada conversa entra na conta
- **Hoje, por amostra — × 3,33:** fora do censo, cada conversa amostrada vale por 3,33 na contagem.
- **Na proposta — 100%** das ~1.340 conversas classificáveis por dia, contadas uma a uma.
- O que hoje escapa volta para a base:
  - **2.725** leads perdidos (11,9%, jun–set) que nunca entraram na VoC passam a ser lidos.
  - **13.328** tickets classificados sem a transcrição que hoje existe são refeitos.
  - **44% → < 5%** é a meta para o balde genérico de categoria; o teste da Taxonomia v1 chegou a 2,9%.

### 6. Cobrir 100% custa menos que a amostra
Custo mensal do Suporte (US$): desenho agêntico atual escalado a 100% **≥ 290**; hoje, por amostra **~135**; proposta cobrindo 100% **30–40**. A proposta cobre a população inteira por menos de um terço do custo da amostra de hoje.
- **−79%** por item no Suporte: de ≈ US$ 0,007 para a meta de ≤ US$ 0,0015.
- **−71% ou mais** na Esteira A: de ~US$ 70–80 para ≤ US$ 20 por mês.
- **−84%** para reprocessar o histórico de ~0,9M itens: de ~US$ 1,9 mil para ~US$ 300.

### 7. De onde vem a economia
- **−26%** de chamadas à IA, eliminando inputs duplicados (−99% na aquisição).
- **91%** do input é um template fixo, que passa a ser reaproveitado em cache.
- **30k → 3–6k** caracteres de taxonomia por prompt, enviando só as categorias relevantes.
- Cascata de modelos: sem IA (~25–35%, vazios, ruído e duplicados) → modelo leve (~60–70%, classificação em lote) → modelo intermediário (~5–10%, casos ambíguos) → modelo avançado (sínteses: nomes de clusters e o Cross mensal).

### 8. Três etapas, sem interromper quem consome
| Etapa | O que acontece | Saída |
|---|---|---|
| Fases 0 e 1 · Arrumar a base atual | Dono da taxonomia, golden set e ganhos rápidos na VoC: retry, dedupe e cache | Mesmos números para quem consome, com menos tokens |
| Fases 2 e 3 · Construir ao lado | Nova esteira e V3 do Suporte em shadow, junto da atual | Qualidade igual ou melhor e custo dentro da meta |
| Fases 4 e 5 · Virar a chave | Demais fontes e Cross na nova esteira, desligar agentes antigos e reprocessar o histórico | Cross gerando oportunidades e série histórica validada |

Sem datas: o prazo de cada fase será dimensionado com os times.

### 9. Como vamos medir o sucesso
| Métrica | Hoje | Meta |
|---|---|---|
| Cobertura do Suporte | Censo parcial + 30% de amostra | 100% |
| Custo por item no Suporte | ≈ US$ 0,007 | ≤ US$ 0,0015 |
| Custo mensal da Esteira A | ~US$ 70–80 | ≤ US$ 20 |
| Balde genérico de categoria | 44% | abaixo de 5% |
| Runs sem intervenção manual | Shards instáveis | ≥ 95% |

Metas propostas, a confirmar com a baseline da Fase 2.

### 10. O que precisamos para começar
- **Pedido:** aprovar o início pelas fases 0 e 1, que corrigem a VoC atual sem mudar os números que os times consomem.
- **Decisões:**
  1. Um dono único para a taxonomia e o prompt, no time de dados.
  2. Datasets próprios da VoC, com dono, permissões e custo isolados.
  3. Reprocessar o histórico ao fim, por ~US$ 300.
- **Pendências técnicas (nas notas):** comparar o código do sense-platform com o To-Be, testar se o AI.GENERATE aproveita cache de prefixo e confirmar no Frame 1 do Miro se a 2.0 roda sem orquestrador.
