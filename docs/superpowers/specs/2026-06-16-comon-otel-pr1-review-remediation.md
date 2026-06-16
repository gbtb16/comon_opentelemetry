# Spec — Remediação da revisão do PR #1 (verificar + corrigir o que de fato precisa)

> **Status:** Proposta para revisão
> **Data:** 2026-06-16
> **Autor:** Síntese de review multi-agente (6 dimensões → verificação adversarial → triagem) + verificação empírica do orquestrador
> **Artefato revisado:** PR #1 de `gbtb16/comon_opentelemetry`, head `fix/mobile-readiness-blockers` (base `main`, +3424/−143, 30 arquivos)
> **Specs/planos-fonte:** `docs/superpowers/specs/2026-06-16-comon-otel-fase1-review-cleanup.md` (M1–M5, já fechados), `docs/superpowers/specs/2026-06-09-comon-otel-mobile-readiness-design.md`, `docs/superpowers/plans/2026-06-15-comon-otel-mobile-blockers.md`

---

## 1. Contexto e objetivo

O PR #1 (Fase 1: B1–B6 + F2.1) passou por uma revisão multi-agente de merge-readiness: 6 revisores por dimensão (resiliência, cardinalidade/correlação, config/lifecycle, recurso/PII, testes/API, docs/composabilidade), cada achado **verificado adversarialmente** contra o código do head do PR (`git show fix/mobile-readiness-blockers:<path>`, não a working tree). Resultado: **35 achados, 12 confirmados, 0 refutados, 0 bloqueadores de código.** A isso somam-se **2 pontos de integração** confirmados pelo orquestrador (deps e CI) e a **verificação empírica local** (analyze + suíte de testes).

Esta spec **não abre escopo de produto**. Ela faz três coisas:

1. **Verificar primeiro** (§4) — os achados cuja necessidade real depende do nosso contexto (deps, CI, alcance do sanitizador sob go_router, raio de impacto da mudança de default do recurso). "O que de fato precisa" sai dessa triagem, não de uma lista crua.
2. **Corrigir** (§5) — o trabalho concreto, do bloqueador aos nits, cada item com origem rastreável (ID do achado + veredito do verificador) e passo TDD onde aplicável.
3. **Registrar sem-ação** (§6) — os achados cuja conclusão verificada é "correto como está", para a revisão não os confundir com esquecimento.

**Objetivo:** deixar o PR num estado em que o merge no `main` do fork seja seguro **e** imediatamente consumível pelo app `PrologFlutter`, sem regressões escondidas nos invariantes do projeto (host nunca quebra · cardinalidade é lei · PII).

---

## 2. Veredito da revisão

**NO-GO como está → GO assim que o bump de deps (B0) entrar.** O código é sólido; o que trava o merge é integração, não lógica.

**Evidência empírica (rodada localmente na working tree, deps `^12`/`^9`):**

- `fvm dart run melos run analyze` → **limpo** nos 3 pacotes.
- `fvm dart run melos run test` → **verde**: `comon_otel_dio +13` · `comon_otel +98` · `comon_otel_flutter +26`. Confirmados empiricamente os casos que pinam invariantes: flush em `paused`/`detached`/`hidden` **e o caso negativo** (`does not flush on non-backgrounding states`), `navigation emits only a sanitized screen_ready span`, e o screen span processor (`stamps active screen` / `never overwrites explicit` / `stamps nothing when no route`).

> ⚠️ Esses números são **auto-reportados quanto ao CI**: o Actions do fork não rodou no PR (P0). A reconciliação acima é a minha execução local, não um artefato de CI.

**O que está forte (sem ação):** B1 (flush-chain throw-safe), B5 (Dio try/catch + `handler.next` sempre nos 3 callbacks), B6 (sem `http.route` client + teste de ausência), B4b (stamping de `screen.name` cross-package sem acoplar Dio↔Flutter, 3 testes), B2 (3 estados + caso negativo). TDD honesto.

---

## 3. Mapa de triagem

| ID | Achado | Origem (dimensão) | Sev. pós-verify | Veredito | Ação (§) |
|---|---|---|---|---|---|
| **B0** | Deps `^11`/`^8` não resolvem contra o app (`^12.2.0`/`^9.0.0`) | orquestrador | **bloqueador** | confirmado | §5.1 |
| **P0** | CI (`pull_request`) configurado mas Actions não roda no fork | orquestrador | major (processo) | confirmado | §4.2 + §5.2 |
| **A1** | `telemetry.sdk.*` ausente do recurso default (detector não wired) | resource-pii | major | confirmado | §5.3 |
| **A2** | Sanitizador de rota: query/fragment/nome-relativo escapam do `:id` | cardinality | major | confirmado | §4.3 + §5.4 |
| **A3** | Guarda de PII iOS (`systemName` ≠ `name`) sem teste; revert fica verde | tests-api | major | confirmado | §5.5 |
| **m1** | README dio: exemplo `spanNameBuilder` com `uri.path` cru + linha `http.route` morta | cardinality | minor | confirmado | §5.6 |
| **m2** | Sem teste de que flags B3 produzem `BatchSpanProcessor`/`PeriodicMetricReader` | config-lifecycle | minor | confirmado | §5.7 |
| **m3** | `CLAUDE.md` com caminho absoluto `/Users/usuario/fvm/...` | docs | minor | confirmado | §5.8 |
| **n1** | `forceFlush()`/`shutdown()` re-propagam se o exporter estourar no teardown | resilience | nit | confirmado | §5.9 |
| **n2** | Enqueue em `onEnd`/`onEmit` fora de try/catch (pré-existente) | resilience | nit | confirmado | §5.10 |
| **n3** | `service.version` é runtime-condicional (só se versão não-vazia) | docs | nit | confirmado | §5.11 |
| **n4** | Contagem de testes do corpo (93) ≠ `CLAUDE.md` (92) ≠ run local (98) | tests-api | nit | confirmado | §5.12 |
| **n5** | Swallow de `onResponse`/`onError` do Dio sem teste de throw forçado | tests-api | minor | confirmado (justificado) | §6 |

---

## 4. Verificar primeiro (antes de corrigir)

### 4.1 — Confirmar o contrato de deps do app (insumo de B0)
Já verificado: `PrologFlutter/pubspec.yaml` exige `device_info_plus: ^12.2.0` e `package_info_plus: ^9.0.0`. O head do PR fixa `^11.0.0`/`^8.0.0` → `^11` (`>=11 <12`) não resolve contra `^12.2.0`. A branch `chore/bump-mobile-deps-for-app` (commit `5753c83`, **1 commit à frente do head, fora do PR**) já sobe pra `^12.0.0`/`^9.0.0`, e o analyze+testes locais confirmam que resolve limpo nesses majors. **Decisão tomada:** dobrar `5753c83` na branch do PR (§5.1).

### 4.2 — Confirmar o estado do GitHub Actions no fork (insumo de P0)
`gh pr checks 1` → "no checks reported", apesar de `ci.yml` ter trigger `pull_request`. **Verificar:** se Actions está desabilitado no fork (Settings → Actions) ou se é só ausência de run. Comando: `gh api repos/gbtb16/comon_opentelemetry/actions/permissions`. Decidir habilitar antes do próximo PR (§5.2).

### 4.3 — Confirmar o alcance real do furo do sanitizador (insumo de A2)
A2 é, antes de tudo, **correção que a lib é dona** — "cardinalidade é lei" vale para o sanitizador incondicionalmente, então o fix se justifica independente de qual app consome. O contexto do app só calibra a **urgência**: o `PrologFlutter` usa **go_router** (`PrologFlutter/lib/core/routing/prolog_router.dart`), não um `routes:` estático, e go_router resolve path params (`/order/:id` → `/order/12345`) e pode propagar query em deep links — exatamente o vetor dos furos. **Verificar (test-first, antes do fix):** (a) confirmar se o app de fato roteia através do `OtelNavigatorObserver` da lib (ele tem o seu próprio `navigation_history_observer.dart` — a integração não foi confirmada nesta revisão); e (b) inspecionar qual string o `OtelNavigatorObserver.didPush` recebe como `route.settings.name` sob a config go_router (location resolvida? com query? nome relativo?). O resultado de (b) vira os casos de teste vermelhos de §5.4 — que valem mesmo se (a) for negativo, porque é correção da lib.

### 4.4 — Confirmar o raio de impacto de mexer no recurso default (insumo de A1)
Adicionar `TelemetrySdkResourceDetector` aos `defaultDetectors` afeta **todos** os consumidores (inclusive os Dart-puro/server), não só o mobile. **Verificar:** nenhum teste existente asserta um conjunto exato de atributos de recurso que quebraria ao ganhar `telemetry.sdk.*`; e que `Resource.autoDetect` faz merge (não duplica chave). Isso é desejado (atributos mandatórios da spec) — só não pode quebrar consumidor silenciosamente.

---

## 5. Trabalho a fazer

> **Branch-alvo:** todo o trabalho desta seção cai em `fix/mobile-readiness-blockers` (a branch do PR), pra fluir direto pro PR #1. O B0 absorve a `chore/bump-mobile-deps-for-app`, que é fechada. (A working tree atual está em `chore/bump` = head do PR + o commit do bump; após B0 as duas convergem.)

### 5.1 — B0 (bloqueador): dobrar o bump de deps na branch do PR
- **Origem:** orquestrador. `^11`/`^8` quebra o `pub get` do app.
- **Fazer:** trazer o commit `5753c83` (`device_info_plus: ^12.0.0`, `package_info_plus: ^9.0.0` em `comon_otel_flutter/pubspec.yaml`) pra dentro de `fix/mobile-readiness-blockers` (cherry-pick ou merge da `chore/bump`), re-bootstrap a partir da raiz (`fvm dart pub get` + `fvm dart run melos bootstrap`), e confirmar analyze+testes verdes. Atualizar a nota "New runtime deps" no corpo do PR pra `^12`/`^9`. Fechar a `chore/bump-mobile-deps-for-app` após dobrar.
- **Pronto:** o PR #1 ship `^12`/`^9`; `melos bootstrap` resolve; `mergeable: CLEAN`.

### 5.2 — P0: habilitar CI no fork
- **Origem:** orquestrador. Validação hoje é auto-reportada.
- **Fazer:** após §4.2, habilitar Actions no fork pro `ci.yml` rodar no `pull_request`. Confirmar que o run cobre `melos run analyze`, `dart format --set-exit-if-changed` e `melos run test` (= dart + flutter) no Flutter 3.38.9 (já no `ci.yml`). Não é bloqueador de código, mas é gate de processo pro merge ter verificação independente.
- **Pronto:** o PR #1 mostra checks verdes do CI, não "no checks reported".

### 5.3 — A1 (major): `telemetry.sdk.*` presente por padrão
- **Origem:** resource-pii. `TelemetrySdkResourceDetector` está definido mas **não wired** — `defaultDetectors = [ProcessResourceDetector(), HostResourceDetector()]` (`comon_otel/lib/src/core/resource.dart:57`), e `autoDetect` cai nos defaults quando `resourceDetectors == null`. Um `Otel.init()` padrão emite zero `telemetry.sdk.{name,language,version}` (mandatórios pela spec). Agravante: `resourceDetectors` **substitui** os defaults, então um caller mobile que dropa `HostResourceDetector` (por PII) precisa re-listar tudo ou perde `telemetry.sdk` silenciosamente.
- **Fazer (decidir na revisão):**
  - **Opção A** — adicionar `TelemetrySdkResourceDetector` aos `defaultDetectors`. Simples; mas ainda "dropável" quando o caller passa uma lista custom.
  - **Opção B (recomendada, com ressalva)** — sempre incluir `telemetry.sdk.*` em `Resource.autoDetect` independente da lista passada (merge garantido), espelhando como um caller mobile dropa `Host` mas **não deveria** conseguir dropar `telemetry.sdk`. Mais robusto pro caso de override por PII. **Tensão a decidir de olhos abertos:** o commit `2e0ae62` deste PR firmou que listas de processor/detector **substituem**, não fazem merge. A Opção B abre uma exceção deliberada a esse contrato só pra esse detector — aceitar a exceção ou preferir a Opção A (que respeita o contrato, ao custo de o detector ser dropável) é a decisão da revisão.
  - Teste: `Otel.init()` padrão **e** `Otel.init(resourceDetectors: [<sem TelemetrySdk>])` ambos resultam em recurso com `telemetry.sdk.name/language/version`.
- **Pronto:** teste vermelho→verde; §4.4 confirmado (nenhum consumidor quebrado).

### 5.4 — A2 (major): endurecer o sanitizador de rota
- **Origem:** cardinality. `_sanitizeRouteName` (`otel_navigator_observer.dart:213`) tem 3 furos: (1) query — `/order/12345?from=push` → último segmento `12345?from=push` falha `^\d+$` e passa cru (vaza id **e** valores de query); (2) fragment `#...` idem; (3) nome sem `/` inicial (`profile/42`) retorna verbatim, `42` nunca colapsa. Real pro app (go_router, §4.3).
- **Fazer (test-first, casos de §4.3):**
  1. Vermelho: testes para `/order/12345?from=push`, `/order/12345#frag`, `profile/42` (relativo), UUID, trailing slash → todos devem colapsar pra `:id`/forma canônica.
  2. Verde: stripar query+fragment antes do split (`name.split('?').first.split('#').first`) e rodar o collapse de segmentos **mesmo sem `/` inicial**.
- **Pronto:** nenhum segmento dinâmico (numérico/UUID) escapa, sob qualquer das 3 formas; testes verdes.

### 5.5 — A3 (major): tornar a guarda de PII iOS testável + unit test
- **Origem:** tests-api. O invariante mais crítico (`ios.systemName`, nunca `ios.name`; `mobile_resource_detector.dart:47`) está protegido por **uma linha sem teste** — trocar de volta pra `name` passa em todo o CI. O único teste é o mapper puro (`mobileResourceAttributesFrom`), que não toca `device_info_plus`. O `Platform.isIOS`/`isAndroid` (dart:io) bloqueia cobertura por unit test sem um seam injetável.
- **Fazer (decisão tomada — tornar testável):**
  1. Injetar um `DeviceInfoPlatform` fake (a interface tem `static set instance` com `verifyToken` via `MockPlatformInterfaceMixin` — confirmado em `device_info_plus_platform_interface`).
  2. Tornar o gate de plataforma injetável em `detectMobileResourceAttributes` (ex.: parâmetro opcional `TargetPlatform`/override de OS, default = plataforma real) para um host test alcançar o ramo iOS.
  3. Teste: fake iOS retornando `IosDeviceInfo(name: 'iPhone de João', systemName: 'iOS', ...)` → assertar `os.name == 'iOS'` **e** que a string do nome do aparelho (`'iPhone de João'`) **não aparece em nenhum valor de atributo**. O teste falha se alguém trocar `systemName` por `name`.
- **Pronto:** teste vermelho (se a guarda for revertida) → verde; cobre iOS e Android.

### 5.6 — m1 (minor): corrigir os exemplos do README do dio
- **Origem:** cardinality. `comon_otel_dio/README.md:62` mostra `spanNameBuilder: (options) => 'api ${options.method} ${options.uri.path}'` — injeta path cru no nome do span (footgun de cardinalidade que o B4a combate). E `:78` lista `| http.route | every request |`, atributo que o B6 removeu (o interceptor nunca seta `httpRoute`; o teste asserta a ausência).
- **Fazer:** ajustar o exemplo do `spanNameBuilder` para não injetar segmento dinâmico cru (ou sanitizar, ou usar só método/host) com uma ressalva sobre cardinalidade; remover a linha `http.route` da tabela de atributos capturados.
- **Pronto:** README não demonstra o footgun nem promete atributo dropado.

### 5.7 — m2 (minor): teste de que os flags B3 produzem os processors/readers
- **Origem:** config-lifecycle. O teste de params (`config_resource_tests.dart:213`) asserta que os flags caem no `OtelConfig`, mas não que `_buildSpanProcessors`/`_buildMetricReaders` emitem de fato `BatchSpanProcessor`/`PeriodicMetricReader`. Os builders leem os flags (verificado), então não é dead — é gap de regressão.
- **Fazer:** teste que, após `Otel.init(useBatchSpanProcessor: true, usePeriodicMetricReader: true, ...)`, inspeciona os processors/readers construídos (tipo `BatchSpanProcessor`/`PeriodicMetricReader`), cobrindo o ramo flag→builder (não o early-return de lista pré-construída).
- **Pronto:** regressão no builder seria pega.

### 5.8 — m3 (minor): tirar o caminho absoluto do `CLAUDE.md`
- **Origem:** docs. `CLAUDE.md:30-32` cravam `/Users/usuario/fvm/versions/3.38.9/bin/...` — morto em qualquer outra máquina.
- **Fazer:** substituir por forma portável (ex.: `$(fvm which dart)`/`$(fvm which flutter)`, ou instrução pra resolver via `fvm`), mantendo a explicação do bug do wrapper fvm 3.2.1. `.fvmrc`/`ci.yml` já pinam 3.38.9 corretamente.
- **Pronto:** guia roda em qualquer máquina de contribuidor.

### 5.9 — n1 (nit): try/catch no teardown de `forceFlush()`/`shutdown()`
- **Origem:** resilience. `_flushBatch` é throw-safe (B1), mas o `await _exporter.forceFlush()`/`shutdown()` final em `batch_span_processor.dart` e `batch_log_processor.dart` não está em try/catch — re-propaga pra quem chamou. Não envenena a pipeline (acontece após o `_flushBatch` resolver); é só completude do "telemetria nunca estoura no host".
- **Fazer:** envolver a chamada final do exporter em try/catch (swallow, mesma decisão de B1; reporte é F2.2 deferido) **ou** documentar que `forceFlush`/`shutdown` podem propagar erro de teardown. Decidir na revisão; baixo risco.

### 5.10 — n2 (nit): enqueue em `onEnd`/`onEmit` fora de try/catch
- **Origem:** resilience. `_queue.addLast(span.toSpanData())` em `onEnd`/`onEmit` roda síncrono no path do host e não está em try/catch. **Pré-existente** (byte-idêntico ao `main`; o PR só mexeu no corpo do `_flushBatch`), e throw é praticamente impossível (`toSpanData` em span já gravado).
- **Fazer:** decisão consciente — (a) deixar como está e registrar como pré-existente fora do escopo B1 (provável), ou (b) envolver o enqueue em try/catch se quiser cobertura total do invariante. Recomendado: (a), documentado.

### 5.11 — n3 (nit): documentar que `service.version` é condicional
- **Origem:** docs. `mobile_resource_detector.dart:23` só emite `service.version` se a versão for não-vazia. Benigno (num app buildado, `PackageInfo` retorna versão real).
- **Fazer:** comentário curto deixando explícito que é runtime-condicional ao `packageInfo.version` não-vazio. Sem mudança de comportamento.

### 5.12 — n4 (nit): reconciliar a contagem de testes
- **Origem:** tests-api. Corpo do PR diz `core 93`; `CLAUDE.md` diz `core 92`; meu run local deu `core 98`. `dio 13` bate; `flutter 26` bate com o corpo. Divergência de ref (head vs branch descendente) + convenção de contagem.
- **Fazer:** após B0, rodar a suíte canônica uma vez e gravar os totais reais no corpo do PR **e** no `CLAUDE.md` ("Totais de referência"), com a mesma ref. Puramente consistência de doc.

---

## 6. Sem ação (confirmado na revisão — registrar, não fazer)

- **n5 — swallow de `onResponse`/`onError` do Dio sem teste de throw forçado.** O verificador confirmou a justificativa do autor: `Span` é `final` (não dá pra subclassar num fake que estoura) e `_takeSpan` é null-safe — não há seam público limpo. Os dois callbacks envolvem telemetria no mesmo try/catch do `onRequest` e sempre chamam `handler.next` (verificado em `otel_dio_interceptor.dart:148-191`); o contrato de `handler.next` nos caminhos happy/5xx/timeout já é coberto. **Não inventar seam.** Comentário explicativo já existe no teste.
- **API inerte `spanNamePrefix`/`routeSpanNamePrefix`** (do spec anterior §6): manter como compat; não remover sem ciclo de deprecação.
- **Fire-and-forget do `unawaited(Otel.forceFlush())` no background** (B2): limitação aceita; sem ação.

---

## 7. Verificação empírica pendente (gates de go-live — herdados, ainda valem)

Continuam válidos os gates da §4 da spec anterior (`2026-06-16-...review-cleanup.md`), agora reforçados:

1. `detectMobileResourceAttributes` em **device real iOS e Android** — `os.name` = `"iOS"`/`"Android"`, **nunca** o nome do aparelho; ausência de `host.name`. (A3 reduz, mas não elimina, esse gate — o unit test cobre a regressão de campo; o device real cobre o platform channel.)
2. Stitch mobile → backend (W3C) no Tempo; span HTTP carrega `screen.name` (B4b).
3. Contra o collector da empresa (staging): OTLP/HTTP JSON aceito; nenhum `http.route` do client no spanmetrics (B6); nenhum `host.name` no resource.
4. Regressões da §7 da design spec: `AlwaysOnSampler` default no client; temporalidade cumulativa; logs em span com `trace_id`/`span_id`.

---

## 8. Critério de pronto

- **B0 dobrado** — PR ship `^12`/`^9`; `melos bootstrap` resolve; `chore/bump` fechada.
- **P0** — Actions habilitado; CI verde no PR (ou decisão registrada se ficar como follow-up).
- **A1, A2, A3** implementados com testes vermelho→verde (A2 com os casos de §4.3; A3 falha se a guarda iOS for revertida).
- **m1–m3** corrigidos; **n1–n4** decididos e aplicados/documentados; **n5** e §6 registrados sem ação.
- Suítes verdes (core/dio/flutter) + `analyze` limpo + `dart format` limpo — idealmente confirmado pelo CI (P0), não só local.
- §7 executada e registrada, ou explicitamente agendada como gate de go-live separado se a revisão decidir que não bloqueia o merge.
