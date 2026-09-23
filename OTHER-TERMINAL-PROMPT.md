# Prompt para la otra instancia de opencode
# Copia todo el contenido desde "INICIO DEL PROMPT" hasta el final

---

## INICIO DEL PROMPT — copiar desde acá

Sos parte del proyecto free-model-comparison. Tu primer trabajo es registrar este proyecto en engram y guardar todo el contexto de la sesión anterior. Hacé lo siguiente en orden:

### Paso 1: Verificar engram
Ejecutá mem_current_project para confirmar que engram ve "free-model-comparison".

### Paso 2: Registrar sesión
Ejecutá mem_session_start con id "fmc-session-2" y directory el cwd actual.

### Paso 3: Guardar contexto (4 memorias)

Usá mem_save con project "free-model-comparison" y session_id "fmc-session-2" para cada una:

**Memoria 1** - topic_key "architecture/privacy-system", type "architecture":
Title: "Privacy-aware model selection system built"
Content: Built privacy-aware free model selection system for OpenCode Zen. 4 scripts + registry. Privacy tiers: 1=strict(none), 2=anonymous(Nemotron), 3=model-improve(MiMo,DeepSeek,Ling), 4=all(MuseSpark trains Meta). Files: privacy-tier-registry.json, privacy-setup.sh, model-selector.sh, check-model-changes.sh, daily-check.sh.

**Memoria 2** - topic_key "privacy-research/model-tiers", type "architecture":
Title: "Free model privacy tiers research"
Content: Tier 2 vs 3: Tier 2 = anonymous logging, NO model training (Nemotron only). Tier 3 = data may improve the model itself (MiMo, DeepSeek, Ling). Muse Spark = tier 4, trains Meta models explicitly. Evidence in privacy-tier-registry.json.

**Memoria 3** - topic_key "project/daily-execution", type "config":
Title: "Daily model check implementation"
Content: daily-check.sh fetches live models from Zen API, compares snapshot, updates registry, re-evaluates assignments. session-start-hook.sh runs once per day. Both respect privacy tier from .privacy-config.

**Memoria 4** - topic_key "project/remaining-tasks", type "discovery":
Title: "Remaining tasks for free-model-comparison"
Content: Model testing cancelled (free-token budget); privacy tier set in `.privacy-config` (`privacy_max_tier`); quiet-daily + model-agnostic selection delivered (PR #1 merged).

### Paso 4: Verificar
Ejecutá mem_search con query "free-model-comparison" para confirmar que todo se guardó.

### Paso 5: Responder
Decime "Engram registrado y contexto guardado" cuando termines.

## FIN DEL PROMPT
